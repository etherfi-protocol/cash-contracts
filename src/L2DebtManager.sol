// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICashDataProvider} from "./interfaces/ICashDataProvider.sol";
import {AccessControlUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable, Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IL2DebtManager} from "./interfaces/IL2DebtManager.sol";
import {IPriceProvider} from "./interfaces/IPriceProvider.sol";
import {IEtherFiCashAaveV3Adapter} from "./interfaces/IEtherFiCashAaveV3Adapter.sol";

/**
 * @title L2 Debt Manager
 * @author @seongyun-ko @shivam-ef
 * @notice Contract to manage lending and borrowing for Cash protocol
 */
contract L2DebtManager is
    IL2DebtManager,
    UUPSUpgradeable,
    AccessControlUpgradeable
{
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    IERC20 public immutable weETH;
    IERC20 public immutable usdc;
    address public immutable etherFiCashSafe;
    IPriceProvider public immutable priceProvider;
    address public immutable aaveV3Adapter;

    mapping(address user => mapping(address token => uint256 amount))
        private _userCollateral;
    mapping(address user => uint256 borrowing) private _userBorrowings;

    mapping(address token => uint256 amount) private _totalCollateralAmounts;
    uint256 private _totalBorrowingAmount;
    uint256 private _liquidationThreshold;

    constructor(
        address _weETH,
        address _usdc,
        address _etherFiCashSafe,
        address _priceProvider,
        address _aaveV3Adapter
    ) {
        weETH = IERC20(_weETH);
        usdc = IERC20(_usdc);
        etherFiCashSafe = _etherFiCashSafe;
        priceProvider = IPriceProvider(_priceProvider);
        aaveV3Adapter = _aaveV3Adapter;
    }

    function initialize(address __owner) external initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, __owner);
        _grantRole(ADMIN_ROLE, __owner);
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function getUserCollateralForToken(
        address user,
        address token
    ) external view returns (uint256, uint256) {
        if (token != address(weETH)) revert InvalidCollateralToken();
        uint256 collateralTokenAmt = _userCollateral[user][token];
        uint256 collateralAmtInUsd = convertCollateralTokenToUsdc(
            address(weETH),
            collateralTokenAmt
        );

        return (collateralTokenAmt, collateralAmtInUsd);
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function liquidationThreshold() external view returns (uint256) {
        return _liquidationThreshold;
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function totalBorrowingAmount() external view returns (uint256) {
        return _totalBorrowingAmount;
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function totalCollateralAmounts()
        external
        view
        returns (Collateral[] memory, uint256)
    {
        Collateral[] memory collaterals = new Collateral[](1);
        collaterals[0] = Collateral({
            token: address(weETH),
            amount: _totalCollateralAmounts[address(weETH)]
        });

        uint256 totalCollateralInUsd = convertCollateralTokenToUsdc(
            address(weETH),
            collaterals[0].amount
        );

        return (collaterals, totalCollateralInUsd);
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function liquidatable(address user) public view returns (bool) {
        return debtRatioOf(user) > _liquidationThreshold;
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function collateralOf(
        address user
    ) public view returns (Collateral[] memory, uint256) {
        Collateral[] memory collaterals = new Collateral[](1);
        collaterals[0] = Collateral({
            token: address(weETH),
            amount: _userCollateral[user][address(weETH)]
        });

        uint256 totalCollateralInUsd = convertCollateralTokenToUsdc(
            address(weETH),
            collaterals[0].amount
        );

        return (collaterals, totalCollateralInUsd);
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function borrowingOf(address user) public view returns (uint256) {
        return _userBorrowings[user];
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function debtRatioOf(address user) public view returns (uint256) {
        uint256 debtValue = _userBorrowings[user];
        uint256 collateralValue = getCollateralValueInUsdc(user);
        if (collateralValue == 0) revert ZeroCollateralValue();

        return (debtValue * 1e4) / collateralValue; // result in basis points
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function remainingBorrowingCapacityInUSDC(
        address user
    ) public view returns (uint256) {
        uint256 maxBorrowingAmount = (getCollateralValueInUsdc(user) *
            _liquidationThreshold) / 1e4;

        return
            maxBorrowingAmount > _userBorrowings[user]
                ? maxBorrowingAmount - _userBorrowings[user]
                : 0;
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function liquidWeEthAmount() public view returns (uint256) {
        return
            weETH.balanceOf(address(this)) -
            _totalCollateralAmounts[address(weETH)];
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function liquidUsdcAmount() public view returns (uint256) {
        return usdc.balanceOf(address(this)) - _totalBorrowingAmount;
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function convertUsdcToCollateralToken(
        address collateralToken,
        uint256 debtUsdcAmount
    ) public view returns (uint256) {
        if (collateralToken != address(weETH)) revert InvalidCollateralToken();
        return (debtUsdcAmount * 1e18) / priceProvider.getWeEthUsdPrice();
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function convertCollateralTokenToUsdc(
        address collateralToken,
        uint256 collateralAmount
    ) public view returns (uint256) {
        if (collateralToken != address(weETH)) revert InvalidCollateralToken();
        return (collateralAmount * priceProvider.getWeEthUsdPrice()) / 1e18;
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function getCollateralValueInUsdc(
        address user
    ) public view returns (uint256) {
        return
            (_userCollateral[user][address(weETH)] *
                priceProvider.getWeEthUsdPrice()) / 1e18;
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function collateralTokens()
        external
        view
        returns (address[] memory tokens)
    {
        tokens = new address[](1);
        tokens[0] = address(weETH);
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function setLiquidationThreshold(
        uint256 newThreshold
    ) external onlyRole(ADMIN_ROLE) {
        emit LiquidationThresholdUpdated(_liquidationThreshold, newThreshold);
        _liquidationThreshold = newThreshold;
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function depositCollateral(address token, uint256 amount) external {
        if (token != address(weETH)) revert UnsupportedCollateralToken();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _totalCollateralAmounts[token] += amount;
        _userCollateral[msg.sender][token] += amount;

        emit DepositedCollateral(msg.sender, token, amount);
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function borrow(address token, uint256 amount) external {
        if (token != address(usdc)) revert InvalidBorrowToken();

        _userBorrowings[msg.sender] += amount;
        _totalBorrowingAmount += amount;

        if (debtRatioOf(msg.sender) > _liquidationThreshold)
            revert InsufficientCollateral();

        if (IERC20(token).balanceOf(address(this)) < amount)
            revert InsufficientLiquidity();

        IERC20(token).safeTransfer(etherFiCashSafe, amount);

        emit Borrowed(msg.sender, token, amount);
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function repay(address token, uint256 amount) external {
        if (token == address(usdc)) _repayWithUSDC(msg.sender, amount);
        else if (token == address(weETH)) _repayWithWeEth(msg.sender, amount);
        else revert InvalidRepayToken();
    }

    // https://docs.aave.com/faq/liquidations
    /**
     * @inheritdoc IL2DebtManager
     */
    function liquidate(address user) external onlyRole(ADMIN_ROLE) {
        if (!liquidatable(user)) revert CannotLiquidateYet();

        uint256 beforeDebtAmount = _userBorrowings[user];
        uint256 beforeCollateralAmount = _userCollateral[user][address(weETH)];
        _repayWithWeEth(user, beforeDebtAmount); // force to repay the entire debt using the collateral

        emit Liquidated(
            user,
            beforeCollateralAmount,
            _userCollateral[user][address(weETH)],
            beforeDebtAmount
        );
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function fundManagementOperation(
        uint8 marketOperationType,
        bytes calldata data
    ) external onlyRole(ADMIN_ROLE) {
        if (marketOperationType == uint8(MarketOperationType.Supply)) {
            (address token, uint256 amount) = abi.decode(
                data,
                (address, uint256)
            );
            _supplyOnAave(token, amount);
        } else if (marketOperationType == uint8(MarketOperationType.Borrow)) {
            (address token, uint256 amount) = abi.decode(
                data,
                (address, uint256)
            );
            _borrowFromAave(token, amount);
        } else if (marketOperationType == uint8(MarketOperationType.Repay)) {
            (address token, uint256 amount) = abi.decode(
                data,
                (address, uint256)
            );
            _repayOnAave(token, amount);
        } else if (marketOperationType == uint8(MarketOperationType.Withdraw)) {
            (address token, uint256 amount) = abi.decode(
                data,
                (address, uint256)
            );
            _withdrawFromAave(token, amount);
        } else if (
            marketOperationType == uint8(MarketOperationType.SupplyAndBorrow)
        ) {
            (
                address tokenToSupply,
                uint256 amountToSupply,
                address tokenToBorrow,
                uint256 amountToBorrow
            ) = abi.decode(data, (address, uint256, address, uint256));
            _supplyAndBorrowOnAave(
                tokenToSupply,
                amountToSupply,
                tokenToBorrow,
                amountToBorrow
            );
        } else revert InvalidMarketOperationType();
    }

    /// Users repay the borrowed USDC in USDC
    function _repayWithUSDC(address user, uint256 repayDebtAmount) internal {
        if (_userBorrowings[user] < repayDebtAmount)
            revert CannotPayMoreThanDebtIncurred();

        usdc.safeTransferFrom(user, address(this), repayDebtAmount);
        _userBorrowings[user] -= repayDebtAmount;
        _totalBorrowingAmount -= repayDebtAmount;

        emit RepaidWithUSDC(user, repayDebtAmount);
    }

    // Use the deposited collateral to pay the debt
    function _repayWithWeEth(address user, uint256 repayDebtAmount) internal {
        uint256 collateralAmountForDebt = convertUsdcToCollateralToken(
            address(weETH),
            repayDebtAmount
        );

        if (_userBorrowings[user] < repayDebtAmount)
            revert CannotPayMoreThanDebtIncurred();

        if (_userCollateral[user][address(weETH)] < collateralAmountForDebt)
            revert InsufficientCollateralToRepay();

        _userBorrowings[user] -= repayDebtAmount;
        _userCollateral[user][address(weETH)] -= collateralAmountForDebt;

        _totalBorrowingAmount -= repayDebtAmount;
        _totalCollateralAmounts[address(weETH)] -= collateralAmountForDebt;

        if (debtRatioOf(user) > _liquidationThreshold)
            revert InsufficientCollateral();

        emit RepaidWithWeEth(user, repayDebtAmount, collateralAmountForDebt);
    }

    function _supplyAndBorrowOnAave(
        address tokenToSupply,
        uint256 amountToSupply,
        address tokenToBorrow,
        uint256 amountToBorrow
    ) internal {
        _delegateCall(
            aaveV3Adapter,
            abi.encodeWithSelector(
                IEtherFiCashAaveV3Adapter.process.selector,
                tokenToSupply,
                amountToSupply,
                tokenToBorrow,
                amountToBorrow
            )
        );
    }

    function _supplyOnAave(address token, uint256 amount) internal {
        _delegateCall(
            aaveV3Adapter,
            abi.encodeWithSelector(
                IEtherFiCashAaveV3Adapter.supply.selector,
                token,
                amount
            )
        );
    }

    function _borrowFromAave(address token, uint256 amount) internal {
        _delegateCall(
            aaveV3Adapter,
            abi.encodeWithSelector(
                IEtherFiCashAaveV3Adapter.borrow.selector,
                token,
                amount
            )
        );
    }

    function _repayOnAave(address token, uint256 amount) internal {
        _delegateCall(
            aaveV3Adapter,
            abi.encodeWithSelector(
                IEtherFiCashAaveV3Adapter.repay.selector,
                token,
                amount
            )
        );
    }

    function _withdrawFromAave(address token, uint256 amount) internal {
        _delegateCall(
            aaveV3Adapter,
            abi.encodeWithSelector(
                IEtherFiCashAaveV3Adapter.withdraw.selector,
                token,
                amount
            )
        );
    }

    function _delegateCall(
        address target,
        bytes memory data
    ) internal returns (bytes memory result) {
        require(target != address(this), "delegatecall to self");

        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Perform delegatecall to the target contract
            let success := delegatecall(
                gas(),
                target,
                add(data, 0x20),
                mload(data),
                0,
                0
            )

            // Get the size of the returned data
            let size := returndatasize()

            // Allocate memory for the return data
            result := mload(0x40)

            // Set the length of the return data
            mstore(result, size)

            // Copy the return data to the allocated memory
            returndatacopy(add(result, 0x20), 0, size)

            // Update the free memory pointer
            mstore(0x40, add(result, add(0x20, size)))

            if iszero(success) {
                revert(result, returndatasize())
            }
        }
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
