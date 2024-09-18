// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuardTransientUpgradeable} from "../utils/ReentrancyGuardTransientUpgradeable.sol";

contract CashWrappedERC20 is Initializable, ERC20Upgradeable, ERC20PermitUpgradeable, ReentrancyGuardTransientUpgradeable {
    using SafeERC20 for IERC20;
    
    uint8 _decimals;
    address public baseToken;
    address public factory;
    mapping (address account => bool isMinter) public isWhitelistedMinter;
    mapping (address account => bool isValidRecipient) public isWhitelistedRecipient;

    event WhitelistMinters(address[] accounts, bool[] whitelists);
    event WhitelistRecipients(address[] accounts, bool[] whitelists);
    event Withdraw(address to, uint256 amount);

    error OnlyWhitelistedMinter();
    error NotAWhitelistedRecipient();
    error OnlyFactory();
    error ArrayLengthMismatch();
    
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address __baseToken, 
        string memory __name, 
        string memory __symbol, 
        uint8 __decimals
    ) external initializer {
        __ERC20_init(__name, __symbol);
        __ERC20Permit_init(__name);
        __ReentrancyGuardTransient_init();
        _decimals = __decimals;
        baseToken = __baseToken;
        factory = msg.sender;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external nonReentrant {
        if (!isWhitelistedMinter[msg.sender]) revert OnlyWhitelistedMinter();
        if (!isWhitelistedRecipient[to]) revert NotAWhitelistedRecipient();

        _mint(to, amount);
        IERC20(baseToken).safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(address to, uint256 amount) external {
        _burn(msg.sender, amount);
        IERC20(baseToken).safeTransfer(to, amount);
        emit Withdraw(to, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (!isWhitelistedRecipient[to]) revert NotAWhitelistedRecipient();
        super.transfer(to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (!isWhitelistedRecipient[to]) revert NotAWhitelistedRecipient();
        super.transferFrom(from, to, amount);
        return true;
    }

    function whitelistMinters(address[] calldata accounts, bool[] calldata whitelists) external onlyFactory {
        _whitelist(isWhitelistedMinter, accounts, whitelists);
        emit WhitelistMinters(accounts, whitelists);
    }

    function whitelistRecipients(address[] calldata accounts, bool[] calldata whitelists) external onlyFactory {
        _whitelist(isWhitelistedRecipient, accounts, whitelists);
        emit WhitelistRecipients(accounts, whitelists);
    }

    function _whitelist(
        mapping (address => bool) storage whitelist, 
        address[] calldata accounts, 
        bool[] calldata whitelists
    ) internal {
        uint256 len = accounts.length;
        if (len != whitelists.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < len; ) {
            whitelist[accounts[i]] = whitelists[i];
            unchecked {
                ++i;
            }
        }
    }

    function _onlyFactory() internal view {
        if (msg.sender != factory) revert OnlyFactory();
    }

    modifier onlyFactory() {
        _onlyFactory();
        _;
    }
}