using MockERC20 as token;

methods {
    function nonce() external returns (uint256) envfree;
    function applicableSpendingLimit() external returns (IUserSafe.SpendingLimitData memory);
    function applicableCollateralLimit() external returns (uint256);
    function token.decimals() external returns (uint8) envfree; 
}

// VERIFIED - except for requestWithdrawal
rule NonceIncreases(env e, method f) filtered {
    f ->   f.selector == (sig:setOwner(bytes, bytes).selector) ||
        f.selector == (sig:resetSpendingLimit(uint8, uint256, bytes).selector) || 
        f.selector == (sig:updateSpendingLimit(uint256, bytes).selector) ||
        f.selector == (sig:setCollateralLimit(uint256, bytes).selector) ||
        f.selector == (sig:requestWithdrawal(address[], uint256[], address, bytes).selector) ||
        f.selector == (sig:setIsRecoveryActive(bool, bytes).selector) ||
        f.selector == (sig:setUserRecoverySigner(address, bytes).selector)
} {
    uint256 noncePre = currentContract.nonce();
    calldataarg args;
    f(e, args);
    uint256 noncePost = currentContract.nonce();

    assert (noncePost - noncePre) == 1;
}

// VERIFIED 
rule UpdateSpendingLimitDoesNotChangeUsedUpAmount(env e, method f) filtered {
    f ->   f.selector == (sig:updateSpendingLimit(uint256, bytes).selector) 
} {
    uint256 usedUpAmountPre = currentContract.applicableSpendingLimit(e).usedUpAmount;
    calldataarg args;
    f(e, args);
    uint256 usedUpAmountPost = currentContract.applicableSpendingLimit(e).usedUpAmount;

    assert usedUpAmountPost == usedUpAmountPre;
}

// VERIFIED
rule ResetSpendingLimit(env e, uint8 spendingLimitType, uint256 limitInUsd, bytes signature) {
    IUserSafe.SpendingLimitData spendingLimitDataBefore = currentContract.applicableSpendingLimit(e);

    resetSpendingLimit(e, spendingLimitType, limitInUsd, signature);

    IUserSafe.SpendingLimitData spendingLimitDataAfter = currentContract.applicableSpendingLimit(e);
    assert ((spendingLimitDataAfter.usedUpAmount == 0) || (spendingLimitDataAfter.usedUpAmount == spendingLimitDataBefore.usedUpAmount));
    assert ((spendingLimitDataAfter.spendingLimit == limitInUsd) || (spendingLimitDataAfter.spendingLimit == spendingLimitDataBefore.spendingLimit));
    assert ((assert_uint8(spendingLimitDataAfter.spendingLimitType) == spendingLimitType) || (assert_uint8(spendingLimitDataAfter.spendingLimitType) == assert_uint8(spendingLimitDataBefore.spendingLimitType)));
} 

rule CollateralLimitDecreasesWhenAddCollateral(env e, uint256 amount) {
    uint8 decimals = token.decimals();
    require decimals > 0 && decimals < 19;

    uint256 collateralLimitPre = currentContract.applicableCollateralLimit(e);
    addCollateral(e, token, amount);
    uint256 collateralLimitPost = currentContract.applicableCollateralLimit(e);
    
    assert collateralLimitPre > collateralLimitPost;
}

rule TransfersIncreasesUsedUpAmountInSpendingLimit(env e, uint256 amount) {
    uint8 decimals = token.decimals();
    require decimals > 0 && decimals < 19;

    uint256 usedUpAmountPre = currentContract.applicableSpendingLimit(e).usedUpAmount;

    transfer(e, token, amount);
    uint256 usedUpAmountPost = currentContract.applicableSpendingLimit(e).usedUpAmount;

    assert usedUpAmountPost > usedUpAmountPre;
}
