// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICashDataProvider} from "./interfaces/ICashDataProvider.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable, Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IL2DebtManager} from "./interfaces/IL2DebtManager.sol";
import {IPriceProvider} from "./interfaces/IPriceProvider.sol";
import {IEtherFiCashAaveV3Adapter} from "./interfaces/IEtherFiCashAaveV3Adapter.sol";

// Consider directly inheriting AAVA pool or routing relevant calls to AAVA pool
contract L2DebtManager is UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    IERC20 public immutable weETH;
    IERC20 public immutable usdc;
    address public immutable etherFiCashSafe;
    IPriceProvider public immutable priceProvider;
    address public immutable aaveV3Adapter;

    mapping(address => uint256) private _collaterals;
    mapping(address => uint256) private _borrowings;

    uint256 public totalCollateralAmount;
    uint256 public totalBorrowingAmount;

    uint256 public liquidationThreshold;

    event SuppliedUSDC(uint256 amount);
    event DepositedCollateral(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event Borrowed(
        address indexed user,
        address indexed token,
        uint256 borrowUsdcAmount
    );
    event RepaidWithUSDC(address indexed user, uint256 repaidUsdcDebtAmount);
    event RepaidWithEETH(
        address indexed user,
        uint256 repaidUsdcDebtAmount,
        uint256 repaidCollateralEEthAmount
    );
    event Liquidated(
        address indexed user,
        uint256 beforeCollateralAmount,
        uint256 afterCollateralAmount,
        uint256 beforeDebtAmount
    );

    error UnsupportedCollateralToken();
    error InsufficientCollateral();
    error InsufficientLiquidity();
    error InvalidRepayToken();
    error CannotLiquidateYet();

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
        __Ownable_init(__owner);
    }

    // function supply(address token, uint256 amount) external {
    //     if (token != usdc && token != weETH) revert InvalidToken();
    //     SafeERC20.safeTransferFrom(usdc, msg.sender, address(this), amount);

    //     emit SuppliedUSDC(amount);
    // }

    function depositCollateral(
        address user,
        address token,
        uint256 amount
    ) external {
        if (token != address(weETH)) revert UnsupportedCollateralToken();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _collaterals[user] += amount;
        totalCollateralAmount += amount;

        emit DepositedCollateral(user, token, amount);
    }

    /// Users borrow funds for payment using the deposited collateral eETH
    /// - the user's borriwng amount is incremented by the exact `amount`
    /// - the total borrowing amount is incremented by the exact `amount`
    /// - the token is transferred to the `etherFiCashSafe`
    function borrow(address token, uint256 amount) external {
        _borrowings[msg.sender] += amount;
        totalBorrowingAmount += amount;

        if (debtRatioOf(msg.sender) > liquidationThreshold)
            revert InsufficientCollateral();

        if (IERC20(token).balanceOf(address(this)) < amount)
            revert InsufficientLiquidity();

        IERC20(token).safeTransfer(etherFiCashSafe, amount);

        emit Borrowed(msg.sender, token, amount);
    }

    function repay(address token, uint256 amount) external {
        if (token == address(usdc)) _repayWithUSDC(msg.sender, amount);
        else if (token == address(weETH)) _repayWithWeEth(msg.sender, amount);
        else revert InvalidRepayToken();
    }

    /// Users repay the borrowed USDC in USDC
    function _repayWithUSDC(address user, uint256 repayUsdcAmount) internal {
        _borrowings[user] -= repayUsdcAmount;
        totalBorrowingAmount -= repayUsdcAmount;

        IERC20(usdc).safeTransferFrom(user, address(this), repayUsdcAmount);

        emit RepaidWithUSDC(user, repayUsdcAmount);
    }

    // https://docs.aave.com/faq/liquidations
    /// Liquidate the user's debt by repaying the entire debt using the collateral
    /// @dev do we need to add penalty?
    function liquidate(address user) external {
        if (!liquidatable(user)) revert CannotLiquidateYet();

        uint256 beforeDebtAmount = _borrowings[user];
        uint256 beforeCollateralAmount = _collaterals[user];
        _repayWithWeEth(user, beforeDebtAmount); // force to repay the entire debt using the collateral

        emit Liquidated(
            user,
            beforeCollateralAmount,
            _collaterals[user],
            beforeDebtAmount
        );
    }

    // View functions
    function liquidatable(address user) public view returns (bool) {
        return debtRatioOf(user) > liquidationThreshold;
    }

    function collateralOf(address user) public view returns (uint256) {
        return _collaterals[user];
    }

    function borrowingOf(address user) public view returns (uint256) {
        return _borrowings[user];
    }

    /// Debt ratio is calculated as the ratio of the debt to the collateral value in USDC
    // it returns the ratio in basis points (1e4)
    function debtRatioOf(address user) public view returns (uint256) {
        uint256 debtValue = _borrowings[user];
        uint256 collateralValue = (_collaterals[user] *
            priceProvider.getWeEthUsdPrice()) / 1e18; // adjust for eETH's 18 decimals

        require(collateralValue > 0, "ZERO_COLLATERAL_VALUE");

        return (debtValue * 1e4) / collateralValue; // result in basis points
    }

    function remainingBorrowingCapacityInUSDC(
        address user
    ) public view returns (uint256) {
        uint256 collateralValue = (_collaterals[user] *
            priceProvider.getWeEthUsdPrice()) / 1e18;
        uint256 maxBorrowingAmount = (collateralValue * liquidationThreshold) /
            1e4;
        return
            maxBorrowingAmount > _borrowings[user]
                ? maxBorrowingAmount - _borrowings[user]
                : 0;
    }

    function liquidEEthAmount() public view returns (uint256) {
        return IERC20(usdc).balanceOf(address(this)) - totalCollateralAmount;
    }

    function liquidUsdcAmount() public view returns (uint256) {
        return IERC20(usdc).balanceOf(address(this)) - totalBorrowingAmount;
    }

    function convertWeEthtoUSDC(
        uint256 eethAmount
    ) private view returns (uint256) {
        return (eethAmount * priceProvider.getWeEthUsdPrice()) / 1e18;
    }

    function getCollateralAmountForDebt(
        uint256 debtUsdcAmount
    ) public view returns (uint256) {
        return (debtUsdcAmount * 1e18) / priceProvider.getWeEthUsdPrice();
    }

    // Internal functions

    // Use the deposited collateral to pay the debt
    function _repayWithWeEth(
        address user,
        uint256 repayDebtAmount
    ) internal returns (uint256 collateralAmount) {
        collateralAmount = getCollateralAmountForDebt(repayDebtAmount);

        _borrowings[user] -= repayDebtAmount;
        _collaterals[user] -= collateralAmount;

        totalBorrowingAmount -= repayDebtAmount;
        totalCollateralAmount -= collateralAmount;

        emit RepaidWithEETH(user, repayDebtAmount, collateralAmount);
    }

    // Setters

    function setLiquidationThreshold(uint256 newThreshold) external onlyOwner {
        liquidationThreshold = newThreshold;
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

    /**
     * @dev internal method that fecilitates the extenral calls from SmartAccount
     * @dev similar to execute() of Executor.sol
     * @param target destination address contract/non-contract
     * @param data function singature of destination
     */
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
    ) internal override onlyOwner {}
}
