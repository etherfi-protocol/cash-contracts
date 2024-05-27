// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "./custom1155.sol";

contract Preorder is 
    CustomERC1155, 
    OwnableUpgradeable,
    PausableUpgradeable, 
    UUPSUpgradeable
    {

    // Gnosis Safe to receive the preorder payments
    address public gnosisSafe;

    // Semi-fungible token with 3 distinct tiers
    enum Tier { Unknown, Low, Medium, Premium }

    // Storages the cost to purchase and the maxSupply for each tier
    struct TierData { 
        uint128 costWei; 
        uint32 maxSupply; 
    }
    mapping(Tier => TierData) public tiers;

    // Contract owner is the timelock, admin role needed to eeform timely actions on the contract
    address public admin;

    function initialize(
        address initialOwner,
        address payable _gnosisSafe,
        uint128 _lowTierCost,
        uint32 _lowTierSupply,
        uint128 _mediumTierCost,
        uint32 _mediumTierSupply,
        uint128 _premiumTierCost,
        uint32 _premiumTierSupply
    ) public initializer {
        __Ownable_init(initialOwner);
        __Pausable_init();

        gnosisSafe = _gnosisSafe;
        admin = _gnosisSafe;

        tiers[Tier.Low] = TierData({
            costWei: _lowTierCost,
            maxSupply: _lowTierSupply
        });
        tiers[Tier.Medium] = TierData({
            costWei: _mediumTierCost,
            maxSupply: _mediumTierSupply
        });
        tiers[Tier.Premium] = TierData({
            costWei: _premiumTierCost,
            maxSupply: _premiumTierSupply
        });
    }

    //--------------------------------------------------------------------------------------
    //--------------------------------  Public ---------------------------------------------
    //--------------------------------------------------------------------------------------

    // Mints a token with ETH
    function Mint(Tier _tier) payable external returns (uint256) {
        require(msg.value == tiers[_tier].costWei, "Incorrect amount sent");

        (bool success, ) = gnosisSafe.call{value: msg.value}("");
        require(success, "Transfer failed");

        // TODO: check maxSupply for tier
        safeMint(msg.sender, uint8(_tier));

        emit Preorder(msg.sender, _tier, msg.value);
    }

    // mints a token with eETH
    function MintWithPermit(Tier _tier, uint256 _amount, uint256 _deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(_amount == tiers[_tier].costWei, "Incorrect amount sent");

        IERC20Permit(eETH).permit(msg.sender, address(this), _amount, _deadline, v, r, s);
        // TODO: check maxSupply for tier
        safeMint(msg.sender, uint8(_tier));


        emit Preorder(msg.sender, _tier, _amount);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERC-1155  ----------------------------------------
    //--------------------------------------------------------------------------------------

    function uri(uint256 id) public view override returns (string memory) {
        // TODO:
        return "";
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  Admin  -------------------------------------------
    //--------------------------------------------------------------------------------------

    // Sets the cost and max supply for a tier
    function setTierData(Tier _tier, uint128 _costWei, uint32 _maxSupply) external onlyAdmin {
        tiers[_tier] = TierData({
            costWei: _costWei,
            maxSupply: _maxSupply
        });
    }

    // Pauses the contract
    function pauseContract() external onlyAdmin {
        _pause();
    }

    // Unpauses the contract
    function unPauseContract() external onlyAdmin {
        _unpause();
    }

    // Updates the admin
    function setAdmin(address _admin) external onlyOwner {
        admin = _admin;
    }

    // Restricts the ability to upgrade the contract to the owner
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    //--------------------------------------------------------------------------------------
    //----------------------------------  Modifiers  ---------------------------------------
    //--------------------------------------------------------------------------------------

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not the admin");
        _;
    }
    
    receive() external payable {
        revert("Direct transfers not allowed");
    }
}
