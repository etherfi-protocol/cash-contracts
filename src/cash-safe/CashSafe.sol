// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {UUPSUpgradeable, Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import { IStargate, Ticket } from "../interfaces/IStargate.sol";
import { MessagingFee, OFTReceipt, SendParam } from "../interfaces/IOFT.sol";

/// @title CashSafe
/// @author shivam@ether.fi
/// @notice This contract receives payments from user safes and bridges it to another chain to pay the fiat provider
contract CashSafe is Initializable, UUPSUpgradeable, AccessControlDefaultAdminRulesUpgradeable {
    using SafeERC20 for IERC20;

    struct DestinationData {
        uint32 destEid;
        address destRecipient;
        address stargate;
    }

    bytes32 public constant BRIDGER_ROLE = keccak256("BRIDGER_ROLE");
    mapping(address token => DestinationData) private _destinationData;

    event DestinationDataSet(address[] tokens, DestinationData[] destDatas);
    event FundsBridgedWithStargate(address indexed token, uint256 amount, Ticket ticket);
    event FundsWithdrawn(address indexed token, uint256 amount, address indexed recipient);

    error ArrayLengthMismatch();
    error InvalidValue();
    error DestinationDataNotSet();
    error StargateValueInvalid();
    error InsufficientBalance();
    error WithdrawFundsFailed();
    error CannotWithdrawZeroAmount();
    error InsufficientFeeToCoverCost();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint48 accessControlDelay,
        address bridger, 
        address[] calldata tokens, 
        DestinationData[] calldata destDatas
    ) external initializer {
        __AccessControlDefaultAdminRules_init(accessControlDelay, msg.sender);
        __UUPSUpgradeable_init();
        _grantRole(BRIDGER_ROLE, bridger);
        _setDestinationData(tokens, destDatas);
    }

    /**
     * @notice Function to fetch the destination data for a token.
     * @param token Address of the token.
     */
    function destinationData(address token) public view returns (DestinationData memory) {
        return _destinationData[token];
    }

    /**
     * @notice Function to set the destination data for an array of tokens.
     * @param tokens Addresses of tokens.
     * @param destDatas DestinationData structs for respective tokens.
     */
    function setDestinationData(
        address[] calldata tokens, 
        DestinationData[] calldata destDatas
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setDestinationData(tokens, destDatas);
    }

    /**
     * @notice Function to bridge funds.
     * @param token Address of the token to bridge.
     * @param amount Amount of the token to bridge.
     */
    function bridge(address token, uint256 amount) external payable onlyRole(BRIDGER_ROLE) {        
        (address stargate, uint256 valueToSend, SendParam memory sendParam, MessagingFee memory messagingFee) = 
            prepareRideBus(token, amount);
        
        if (address(this).balance < valueToSend) revert InsufficientFeeToCoverCost();

        IERC20(token).forceApprove(stargate, amount);
        (, , Ticket memory ticket) = IStargate(stargate).sendToken{ value: valueToSend }(sendParam, messagingFee, payable(address(this)));
        emit FundsBridgedWithStargate(token, amount, ticket);
    }

    // from https://stargateprotocol.gitbook.io/stargate/v/v2-developer-docs/integrate-with-stargate/how-to-swap#ride-the-bus
    function prepareRideBus(
        address token,
        uint256 amount
    ) public view returns (address stargate, uint256 valueToSend, SendParam memory sendParam, MessagingFee memory messagingFee) {
        if (token == address(0) || amount == 0) revert InvalidValue();
        if (IERC20(token).balanceOf(address(this)) < amount) revert InsufficientBalance();

        DestinationData memory destData = _destinationData[token];
        if (destData.destRecipient == address(0)) revert DestinationDataNotSet();

        stargate = destData.stargate;
        sendParam = SendParam({
            dstEid: destData.destEid,
            to: bytes32(uint256(uint160(destData.destRecipient))),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: new bytes(0),
            composeMsg: new bytes(0),
            oftCmd: new bytes(1)
        });

        (, , OFTReceipt memory receipt) = IStargate(stargate).quoteOFT(sendParam);
        sendParam.minAmountLD = receipt.amountReceivedLD;

        messagingFee = IStargate(stargate).quoteSend(sendParam, false);
        valueToSend = messagingFee.nativeFee;

        if (IStargate(stargate).token() == address(0x0)) {
            valueToSend += sendParam.amountLD;
        }
    }

    function withdrawFunds(address token, address recipient, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (recipient == address(0)) revert InvalidValue();

        if (token == address(0)) {
            if (amount == 0) amount = address(this).balance;
            if (amount == 0) revert CannotWithdrawZeroAmount();
            (bool success, ) = payable(recipient).call{value: amount}("");
            if (!success) revert  WithdrawFundsFailed();
        } else {
            if (amount == 0) amount = IERC20(token).balanceOf(address(this));
            if (amount == 0) revert CannotWithdrawZeroAmount();
            IERC20(token).safeTransfer(recipient, amount);
        }
    }

    function _setDestinationData(address[] calldata tokens, DestinationData[] calldata destDatas) internal {
        uint256 len = tokens.length;
        if (len != destDatas.length) revert ArrayLengthMismatch(); 

        for (uint256 i = 0; i < len; ) {
            if (tokens[i] == address(0) || destDatas[i].destRecipient == address(0) || 
                destDatas[i].stargate == address(0)) revert InvalidValue(); 
            if (IStargate(destDatas[i].stargate).token() != tokens[i]) revert StargateValueInvalid();

            _destinationData[tokens[i]] = destDatas[i];
            unchecked {
                ++i;
            }
        }

        emit DestinationDataSet(tokens, destDatas);
    }

   function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // Added to receive fee refunds from stargate
    receive() external payable {}
}