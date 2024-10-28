using MockERC20 as token;
using CashDataProvider as cashDataProvider;

methods {
    function nonce() external returns (uint256) envfree;
    function cashDataProvider() external returns (address) envfree;
    function applicableSpendingLimit() external returns (UserSafe.SpendingLimit memory);
    function applicableCollateralLimit() external returns (uint256);
    function owner() external returns (OwnerLib.OwnerObject memory);

    function token.decimals() external returns (uint8) envfree; 
    function token.balanceOf(address account) external returns (uint256) envfree; 
    function token.totalSupply() external returns (uint256) envfree; 

    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
    // function _.updateSpendingLimit(UserSafe.SpendingLimit spendingLimit, uint256 dailyLimit, uint256 monthlyLimit, uint64 delay) external => DISPATCHER(true);

    function cashDataProvider.etherFiCashDebtManager() external returns (address) envfree;
    function cashDataProvider.settlementDispatcher() external returns (address) envfree;
}


ghost mathint sumOfBalances {
    init_state axiom sumOfBalances == 0;
}

hook Sload uint256 balance token._balances[KEY address addr] {
    require sumOfBalances >= balance;
}

hook Sstore token._balances[KEY address addr] uint256 newValue (uint256 oldValue) {
    sumOfBalances = sumOfBalances - oldValue + newValue;
}


// invariant totalSupplyIsSumOfBalances()
//     token.totalSupply() == sumOfBalances;


definition initialized(env e) returns bool = 
    currentContract.applicableSpendingLimit(e).dailyRenewalTimestamp > 0 && 
    currentContract.applicableSpendingLimit(e).monthlyRenewalTimestamp > 0 && 
    currentContract.applicableSpendingLimit(e).spentToday == 0 && 
    currentContract.applicableSpendingLimit(e).spentThisMonth == 0 && 
    (
        currentContract.owner(e).ethAddr != 0 || 
        (currentContract.owner(e).x != 0 && currentContract.owner(e).y != 0)
    ) && currentContract._cashDataProvider == cashDataProvider 
    && cashDataProvider._settlementDispatcher == cashDataProvider.settlementDispatcher();

// // VERIFIED - except for requestWithdrawal
// rule NonceIncreases(env e, method f) filtered {
//     f ->   f.selector == (sig:setOwner(bytes, bytes).selector) ||
//         f.selector == (sig:updateSpendingLimit(uint256, uint256, bytes).selector) ||
//         f.selector == (sig:setCollateralLimit(uint256, bytes).selector) ||
//         f.selector == (sig:requestWithdrawal(address[], uint256[], address, bytes).selector) ||
//         f.selector == (sig:setIsRecoveryActive(bool, bytes).selector) ||
//         f.selector == (sig:setUserRecoverySigner(address, bytes).selector)
// } {
//     require initialized(e);
//     uint256 noncePre = currentContract.nonce();
//     calldataarg args;
//     f(e, args);
//     uint256 noncePost = currentContract.nonce();

//     assert (noncePost - noncePre) == 1;
// }

// // VERIFIED 
// rule UpdateSpendingLimitDoesNotChangeUsedUpAmount(env e, uint256 dailyLimit, uint256 monthlyLimit, bytes signature) {
//     require initialized(e);
//     uint256 usedUpAmountTodayPre = currentContract.applicableSpendingLimit(e).spentToday;
//     uint256 usedUpAmountMonthlyPre = currentContract.applicableSpendingLimit(e).spentThisMonth;
//     updateSpendingLimit(e, dailyLimit, monthlyLimit, signature);
//     uint256 usedUpAmountTodayPost = currentContract.applicableSpendingLimit(e).spentToday;
//     uint256 usedUpAmountMonthlyPost = currentContract.applicableSpendingLimit(e).spentThisMonth;

//     assert usedUpAmountTodayPost == usedUpAmountTodayPre;
//     assert usedUpAmountMonthlyPost == usedUpAmountMonthlyPre;
// }

// rule CollateralLimitDecreasesWhenAddCollateral(env e, uint256 amount) {
//     require initialized(e);
//     require e.block.timestamp < currentContract._incomingCollateralLimitStartTime;
//     require cashDataProvider.etherFiCashDebtManager() != currentContract;
//     require amount != 0;

//     uint256 collateralLimitPre = currentContract.applicableCollateralLimit(e);
//     require collateralLimitPre != 0;

//     addCollateral(e, token, amount);
//     uint256 collateralLimitPost = currentContract.applicableCollateralLimit(e);
    
//     assert collateralLimitPre > collateralLimitPost;
// }

// rule TransfersIncreasesUsedUpAmountInSpendingLimit(env e, uint256 amount) {
//     require initialized(e);
//     require e.block.timestamp < currentContract.applicableSpendingLimit(e).dailyLimitChangeActivationTime;
//     require e.block.timestamp < currentContract.applicableSpendingLimit(e).monthlyLimitChangeActivationTime;
//     require amount != 0;

//     uint256 usedUpAmountTodayPre = currentContract.applicableSpendingLimit(e).spentToday;
//     uint256 usedUpAmountMonthPre = currentContract.applicableSpendingLimit(e).spentThisMonth;
//     transfer(e, token, amount);
//     uint256 usedUpAmountTodayPost = currentContract.applicableSpendingLimit(e).spentToday;
//     uint256 usedUpAmountMonthPost = currentContract.applicableSpendingLimit(e).spentThisMonth;

//     assert usedUpAmountTodayPost > usedUpAmountTodayPre;
//     assert usedUpAmountMonthPost > usedUpAmountMonthPre;
// }

rule TransferIncreasesSettlementDispatcherBalance(env e, uint256 amount) {
    require initialized(e);
    require amount != 0;

    address settlementDispatcher = cashDataProvider.settlementDispatcher();
    require settlementDispatcher != currentContract;
    
    uint256 settlementDispatcherBalPre = token.balanceOf(settlementDispatcher);
    uint256 userSafeBalPre = token.balanceOf(currentContract);
    transfer(e, token, amount);
    uint256 settlementDispatcherBalPost = token.balanceOf(settlementDispatcher);
    uint256 userSafeBalPost = token.balanceOf(currentContract);

    assert settlementDispatcherBalPost - settlementDispatcherBalPre == amount;
    assert userSafeBalPre - userSafeBalPost == amount;
}