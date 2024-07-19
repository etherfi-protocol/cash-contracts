// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@aave/pool/Pool.sol";
import "@aave/libraries/types/DataTypes.sol";
import "@aave/libraries/math/WadRayMath.sol";
import "@aave/libraries/math/PercentageMath.sol";

import "../src/interfaces/IERC20.sol";

contract AaveUnitTest is Test {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    // The aave pool contract is the main entry point for the Aave. Most user interactions with the aave 
    // protocol occur via the pool contract.
    Pool aavePool;
    IERC20 weth;
    IERC20 usdc;

    address constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address cashProtocol = vm.addr(1);

    struct AaveAccountData {
        uint256 totalCollateralETH;
        uint256 totalDebtETH;
        uint256 availableBorrowsETH;
        uint256 currentLiquidationThreshold; // ltv liquidation threshold in basis points
        uint256 ltv; // loan to value ration in basis points
        uint256 healthFactor; 
    }

    function setUp() public {
        vm.createSelectFork("https://ethereum-rpc.publicnode.com");

        aavePool = Pool(AAVE_POOL);
        weth = IERC20(WETH);
        usdc = IERC20(USDC);

        deal(WETH, cashProtocol, 1000 ether);
        deal(USDC, cashProtocol, dollarsToWei(10_000));

        vm.startPrank(cashProtocol);
    }

    // calculate the health factor of the cash protocol
    function test_healthFactor() public {
        weth.approve(address(aavePool), 50 ether);
        aavePool.supply(WETH, 50 ether, cashProtocol, 0);
        AaveAccountData memory accountBeforeBorrow = getStructuredAccountData(cashProtocol);

        aavePool.borrow(USDC, dollarsToWei(10_000), 2, 0, cashProtocol);
        AaveAccountData memory accountAfterBorrow = getStructuredAccountData(cashProtocol);

        // `ltv` is an upperbound on how much can be borrowed. Evolves based on market conditions
        assertEq(accountBeforeBorrow.ltv, accountAfterBorrow.ltv);

        // health factor is infinite before borrowing
        assertEq(accountBeforeBorrow.healthFactor, type(uint256).max);

        // totalCollateralETH * averageLiqidationthreshold / totalDebtETH
        // wad has 18 digits of precision like 
        uint256 healthFactorAfter = accountAfterBorrow.totalCollateralETH.percentMul(accountAfterBorrow.currentLiquidationThreshold).wadDiv(accountAfterBorrow.totalDebtETH);
        assertEq(accountAfterBorrow.healthFactor, healthFactorAfter);
    }



    // ========================== HELPERS ==========================
    
    function getStructuredAccountData(address user) public view returns (AaveAccountData memory) {
        (uint256 totalCollateralETH, uint256 totalDebtETH, uint256 availableBorrowsETH, uint256 currentLiquidationThreshold, uint256 ltv, uint256 healthFactor) = aavePool.getUserAccountData(user);
        
        return AaveAccountData({
            totalCollateralETH: totalCollateralETH,
            totalDebtETH: totalDebtETH,
            availableBorrowsETH: availableBorrowsETH,
            currentLiquidationThreshold: currentLiquidationThreshold,
            ltv: ltv,
            healthFactor: healthFactor
        });
    }

    function logStructuredAccountData(AaveAccountData memory data) public view {
        console.log("totalCollateralETH: ", data.totalCollateralETH);
        console.log("totalDebtETH: ", data.totalDebtETH);
        console.log("availableBorrowsETH: ", data.availableBorrowsETH);
        console.log("currentLiquidationThreshold: ", data.currentLiquidationThreshold);
        console.log("ltv: ", data.ltv);
        console.log("healthFactor: ", data.healthFactor);
    }

    function dollarsToWei(uint256 amount) public pure returns (uint256) {
        // 1 USDC = 1e6
        return amount * 1e6;
    }

}