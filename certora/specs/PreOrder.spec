methods {
    function maxSupply() external returns (uint256) envfree;
    function balanceOf(address,uint256) external returns (uint256) envfree;
}

/// @title Functions filtered out since they use `delegatecall`
definition isFilteredFunc(method f) returns bool = (
    f.selector == sig:upgradeToAndCall(address, bytes).selector
);


rule mintingPossible(uint8 _tier) {

    env e;

    mint(e, _tier);
    satisfy true;
}

rule arrayLengthNeverExceedsInitialSize(method f) {
    //require isFilteredFunc();

    mathint preLength = maxSupply();

    env e;
    calldataarg args;
    f(e, args);

    mathint postLength = maxSupply();

    // QUESTION: how do I handle array of structs in spec file sig?
    assert preLength != postLength => f.selector == sig:initialize(address,address,address,address,string,PreOrder.TierConfig[]).selector;
}

/// @title balance of any given token can never exceed 1
rule balanceOfTokenNeverExceedsOne(address _addr, uint256 _tokenId) {
    assert balanceOf(_addr, _tokenId) <= 1;
}

/// @title token can't exist with ID larger than array
rule mintedTokenIdNeverExceedsArrayLength(address _addr, uint256 _tokenId) {
    assert balanceOf(_addr, _tokenId) >= 1 => _tokenId < maxSupply();
}

/*
/// @title address that minted should own token
rule minterIsOwnerOfToken() {
    
    env e;
    mint(
*/
    

