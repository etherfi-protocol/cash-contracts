// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.24;

// import "forge-std/Test.sol";
// import "@aave/protocol/pool/Pool.sol";
// import "@aave/protocol/libraries/types/DataTypes.sol";
// import "@aave/protocol/libraries/math/WadRayMath.sol";
// import "@aave/protocol/libraries/math/PercentageMath.sol";

// import "../src/interfaces/IERC20.sol";

// contract AaveUnitTest is Test {
//     using WadRayMath for uint256;
//     using PercentageMath for uint256;

//     // The aave pool contract is the main entry point for the Aave. Most user interactions with the aave
//     // protocol occur via the pool contract.
//     Pool aavePool;
//     IERC20 weth;
//     IERC20 usdc;

//     address constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
//     address constant AAVE_POOL_CONFIGURATOR =
//         0x64b761D848206f447Fe2dd461b0c635Ec39EbB27;
//     address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
//     address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

//     address cashProtocol = vm.addr(1);

//     struct AaveAccountData {
//         uint256 totalCollateralBase;
//         uint256 totalDebtBase;
//         uint256 availableBorrowsBase;
//         uint256 currentLiquidationThreshold; // ltv liquidation threshold in basis points
//         uint256 ltv; // loan to value ration in basis points
//         uint256 healthFactor;
//     }

//     function setUp() public {
//         vm.createSelectFork("https://ethereum-rpc.publicnode.com");

//         aavePool = Pool(AAVE_POOL);
//         weth = IERC20(WETH);
//         usdc = IERC20(USDC);

//         deal(WETH, cashProtocol, 1000 ether);
//         deal(USDC, cashProtocol, dollarsToUSDC(10_000));

//         vm.startPrank(cashProtocol);
//     }

//     // calculate the health factor of the cash protocol
//     function test_healthFactor() public {
//         weth.approve(address(aavePool), 50 ether);
//         aavePool.supply(WETH, 50 ether, cashProtocol, 0);
//         AaveAccountData memory accountBeforeBorrow = getStructuredAccountData(
//             cashProtocol
//         );

//         aavePool.borrow(USDC, dollarsToUSDC(10_000), 2, 0, cashProtocol);
//         AaveAccountData memory accountAfterBorrow = getStructuredAccountData(
//             cashProtocol
//         );

//         // `ltv` is an upperbound on how much can be borrowed. Evolves based on market conditions
//         assertEq(accountBeforeBorrow.ltv, accountAfterBorrow.ltv);

//         // health factor is infinite before borrowing
//         assertEq(accountBeforeBorrow.healthFactor, type(uint256).max);

//         // totalDebtBase * averageLiqidationthreshold / availableBorrowsBase
//         // wad has 18 digits of precision like wei
//         uint256 healthFactorAfter = accountAfterBorrow
//             .totalCollateralBase
//             .percentMul(accountAfterBorrow.currentLiquidationThreshold)
//             .wadDiv(accountAfterBorrow.totalDebtBase);
//         assertEq(accountAfterBorrow.healthFactor, healthFactorAfter);
//     }

//     // simple full flow of supply -> borrow -> supply more -> borrow more -> repay -> withdraw
//     function test_fullFlow() public {
//         AaveAccountData memory accountAfterBorrow = init_position(
//             5 ether,
//             dollarsToUSDC(1_000)
//         );
//         assertApproxEqAbs(
//             dollarsToUSDA(1_000),
//             accountAfterBorrow.totalDebtBase,
//             5e8
//         );

//         // over borrow
//         uint256 overBorrowAmount = accountAfterBorrow.availableBorrowsBase +
//             dollarsToUSDA(5);
//         // convert amount from USD on aave to USDC
//         overBorrowAmount = overBorrowAmount / 1e2;

//         // see here for errors codes
//         // https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/helpers/Errors.sol
//         vm.expectRevert(bytes("36"));
//         aavePool.borrow(USDC, overBorrowAmount, 2, 0, cashProtocol);

//         // supply 10 USDC to the protocol
//         usdc.approve(address(aavePool), dollarsToUSDC(10));
//         aavePool.supply(USDC, dollarsToUSDC(10), cashProtocol, 0);

//         // borrow more
//         aavePool.borrow(USDC, overBorrowAmount, 2, 0, cashProtocol);

//         // repay the full debt
//         uint256 fullDebt = overBorrowAmount + dollarsToUSDC(1_000);
//         usdc.approve(address(aavePool), fullDebt);
//         aavePool.repay(USDC, fullDebt, 2, cashProtocol);

//         assertEq(
//             getStructuredAccountData(cashProtocol).healthFactor,
//             type(uint256).max
//         );

//         // withdraw the ETH collateral
//         aavePool.withdraw(WETH, 5 ether, cashProtocol);
//     }

//     // ========================== HELPERS ==========================

//     // supplys and borrows in aave and returns the positon state after
//     function init_position(
//         uint256 supplyAmount,
//         uint256 borrowAmount
//     ) public returns (AaveAccountData memory) {
//         weth.approve(address(aavePool), supplyAmount);
//         aavePool.supply(WETH, supplyAmount, cashProtocol, 0);
//         aavePool.borrow(USDC, borrowAmount, 2, 0, cashProtocol);

//         return getStructuredAccountData(cashProtocol);
//     }

//     function getStructuredAccountData(
//         address user
//     ) public view returns (AaveAccountData memory) {
//         (
//             uint256 totalCollateralBase,
//             uint256 totalDebtBase,
//             uint256 availableBorrowsBase,
//             uint256 currentLiquidationThreshold,
//             uint256 ltv,
//             uint256 healthFactor
//         ) = aavePool.getUserAccountData(user);

//         return
//             AaveAccountData({
//                 totalCollateralBase: totalCollateralBase,
//                 totalDebtBase: totalDebtBase,
//                 availableBorrowsBase: availableBorrowsBase,
//                 currentLiquidationThreshold: currentLiquidationThreshold,
//                 ltv: ltv,
//                 healthFactor: healthFactor
//             });
//     }

//     function logStructuredAccountData(AaveAccountData memory data) public view {
//         console.log("totalCollateralBase: ", data.totalCollateralBase);
//         console.log("totalDebtBase: ", data.totalDebtBase);
//         console.log("availableBorrowsBase: ", data.availableBorrowsBase);
//         console.log(
//             "currentLiquidationThreshold: ",
//             data.currentLiquidationThreshold
//         );
//         console.log("ltv: ", data.ltv);
//         console.log("healthFactor: ", data.healthFactor);
//     }

//     // 1 USDC == 1e6
//     function dollarsToUSDC(uint256 amount) public pure returns (uint256) {
//         return amount * 1e6;
//     }

//     // 1 USD in Aave == 1e8
//     function dollarsToUSDA(uint256 amount) public pure returns (uint256) {
//         return amount * 1e8;
//     }

//     // gets the `ltv` and `liquidationThreshold` of the pool
//     function getPoolLiquidationData()
//         public
//         view
//         returns (DataTypes.ReserveConfigurationMap memory)
//     {
//         return aavePool.getConfiguration(USDC);
//     }

//     // gets the `borrowCap` and `supplyCap` of the pool
//     function getPoolCaps()
//         public
//         view
//         returns (DataTypes.ReserveConfigurationMap memory)
//     {
//         return aavePool.getConfiguration(USDC);
//     }
// }
