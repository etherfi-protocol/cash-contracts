// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "./custom1155.sol";

contract PreOrder is 
    CustomERC1155, 
    OwnableUpgradeable,
    PausableUpgradeable, 
    UUPSUpgradeable
    {

    // Gnosis Safe to receive the preorder payments
    address payable public gnosisSafe;

    // Semi-fungible token with 3 distinct tiers
    enum Tier { Unknown, Low, Medium, Premium }

    // Storages the cost to purchase and the maxSupply for each tier
    struct TierData { 
        uint128 costWei; 
        uint32 maxSupply;
        uint32 minted;
    }
    mapping(Tier => TierData) public tiers;

    // Contract owner is the timelock, admin role needed to eeform timely actions on the contract
    address public admin;

    // eETH can also be used as a payment
    address public eEthToken;

    // NFT metadata storage location
    string private baseURI;

    // Event emitted when a PreOrder Token is minted
    event PreOrderMint(address indexed buyer, Tier indexed tier, uint256 amount);

    function initialize(
        address initialOwner,
        address payable _gnosisSafe,
        address _admin,
        address _eEthToken,
        string memory _baseURI,
        TierData memory lowTierData,
        TierData memory mediumTierData,
        TierData memory premiumTierData
    ) public initializer {
        require(
            lowTierData.minted == 0 && mediumTierData.minted == 0 && premiumTierData.minted == 0,
            "Tier minted must be 0"
        );

        __Ownable_init(initialOwner);
        __Pausable_init();

        gnosisSafe = _gnosisSafe;
        admin = _admin;
        eEthToken = _eEthToken;
        baseURI = _baseURI;

        tiers[Tier.Low] = lowTierData;
        tiers[Tier.Medium] = mediumTierData;
        tiers[Tier.Premium] = premiumTierData;
    }

    //--------------------------------------------------------------------------------------
    //--------------------------------  Public ---------------------------------------------
    //--------------------------------------------------------------------------------------

    // Mints a token with ETH as payment
    function Mint(Tier _tier) payable external {
        require(msg.value == tiers[_tier].costWei, "Incorrect amount sent");
        require(tiers[_tier].minted < tiers[_tier].maxSupply, "Tier sold out");

        (bool success, ) = gnosisSafe.call{value: msg.value}("");
        require(success, "Transfer failed");

        safeMint(msg.sender, uint8(_tier));

        tiers[_tier].minted += 1;

        emit PreOrderMint(msg.sender, _tier, msg.value);
    }

    // mints a token with eETH as payment
    function MintWithPermit(Tier _tier, uint256 _amount, uint256 _deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(_amount == tiers[_tier].costWei, "Incorrect amount sent");
        require(tiers[_tier].minted < tiers[_tier].maxSupply, "Tier sold out");

        IERC20Permit(eEthToken).permit(msg.sender, address(this), _amount, _deadline, v, r, s);

        IERC20(eEthToken).transferFrom(msg.sender, gnosisSafe, _amount);

        safeMint(msg.sender, uint8(_tier));

        tiers[_tier].minted += 1;   

        emit PreOrderMint(msg.sender, _tier, _amount);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERC-1155  ----------------------------------------
    //--------------------------------------------------------------------------------------

    function uri(uint256 id) public view override returns (string memory) {
        return string(abi.encodePacked(baseURI, Strings.toString(id), ".json"));
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  Admin  -------------------------------------------
    //--------------------------------------------------------------------------------------

    // Sets the mint price for a tier 
    function setTierData(Tier _tier, uint128 _costWei) external onlyAdmin {
        tiers[_tier].costWei = _costWei;
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
