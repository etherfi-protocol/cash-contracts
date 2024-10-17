methods {
    function owner() external returns (address) envfree;
    function defaultAdminDelay() external returns (uint48) envfree;
    function cashDataProvider() external returns (address) envfree;
    function cashTokenWrapperFactory() external returns (address) envfree;
    function totalBorrowingAmounts() external returns (DebtManagerStorage.TokenData[] memory, uint256);
    function borrowingOf() external returns (DebtManagerStorage.TokenData[] memory, uint256);
}


definition initialized() returns bool = 
    currentContract.owner() != 0 && 
    currentContract.defaultAdminDelay() != 0 && 
    currentContract.cashDataProvider() != 0 && 
    currentContract.cashTokenWrapperFactory() != 0;

rule Borrow(env e, address token, uint256 amount) {
    require initialized();
    address user = e.msg.sender;

    uint256 borrowingOfUserPre = borrowingOf(e, user)[1];
    uint256 totalBorrowingsPre = totalBorrowingAmounts(e)[1];
    borrow(e, token, amount);
    uint256 borrowingOfUserPost = borrowingOf(e, user)[1];
    uint256 totalBorrowingsPost = totalBorrowingAmounts(e)[1];

    assert borrowingOfUserPost > borrowingOfUserPre;
    assert totalBorrowingsPost > totalBorrowingsPre;
}
