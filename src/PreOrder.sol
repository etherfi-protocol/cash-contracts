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
    OwnableUpgradeable,
    PausableUpgradeable, 
    UUPSUpgradeable,
    CustomERC1155
    {

    // Gnosis Safe to receive the preorder payments
    address payable public gnosisSafe;

    // Storages the data for each tier
    // Number of tiers is configurable upon initialization
    //  * - tiers[0] -> TierData for Tier 0
    //  * - tiers[1] -> TierData for Tier 1
    //  ....
    //  * - tiers[n] -> TierData for Tier n
    mapping(uint256 => TierData) public tiers;

    // Configurable parameters for each tier
    struct TierData { 
        uint128 costInGwei; 
        uint32 maxSupply;
        uint32 mintCount;
    }

    // Contract owner is the timelock, admin role needed to eeform timely actions on the contract
    address public admin;

    // eETH can also be used as a payment
    address public eEthToken;

    // NFT metadata storage location
    string private baseURI;

    // Event emitted when a PreOrder Token is mintCount
    event PreOrderMint(address indexed buyer, uint256 indexed tier, uint256 amount);

    function initialize(
        address initialOwner,
        address _gnosisSafe,
        address _admin,
        address _eEthToken,
        string memory _baseURI,
        TierData[] memory tierDataArray
    ) public initializer {

        __Ownable_init(initialOwner);
        __Pausable_init();

        gnosisSafe = payable(_gnosisSafe);
        admin = _admin;
        eEthToken = _eEthToken;
        baseURI = _baseURI;

        uint256 totalCards;
        for (uint256 i = 0; i < tierDataArray.length; i++) {
            require(tierDataArray[i].mintCount == 0, "Tier mintCount must be 0");
            tiers[i] = tierDataArray[i];
            totalCards += tierDataArray[i].maxSupply;
        }

        // If we decide we want infinite of the last tier, we can just statically
        // initialize to a giant number instead of doing this
        assembly {
            sstore(tokens.slot, totalCards)
        }
    }

    //--------------------------------------------------------------------------------------
    //--------------------------------  Public ---------------------------------------------
    //--------------------------------------------------------------------------------------

    // Mints a token with ETH as payment
    function mint(uint8 _tier) payable external {
        require(msg.value == tiers[_tier].costWei, "Incorrect amount sent");
        require(tiers[_tier].mintCount < tiers[_tier].maxSupply, "Tier sold out");

        (bool success, ) = gnosisSafe.call{value: msg.value}("");
        require(success, "Transfer failed");

        safeMint(msg.sender, _tier, calculateTokenId(_tier));

        emit PreOrderMint(msg.sender, _tier, msg.value);
    }

    // Mints a token with eETH as payment
    function MintWithPermit(uint8 _tier, uint256 _amount, uint256 _deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(_amount == tiers[_tier].costInGwei, "Incorrect amount sent");
        require(tiers[_tier].mintCount < tiers[_tier].maxSupply, "Tier sold out");

        IERC20Permit(eEthToken).permit(msg.sender, address(this), _amount, _deadline, v, r, s);

        IERC20(eEthToken).transferFrom(msg.sender, gnosisSafe, _amount);

        safeMint(msg.sender, _tier, calculateTokenId(_tier));

        tiers[_tier].mintCount += 1;   

        emit PreOrderMint(msg.sender, _tier,  _amount);
    }

    function maxSupply() external view returns (uint256) {
        return tokens.length;
    }

    // Helper function to calculate the tokenId
    function calculateTokenId(uint256 _tier) internal view returns (uint256 tokenId) {
        if (_tier == 0) {
            tokenId = tiers[_tier].mintCount;
        } else {
            tokenId = tiers[_tier].mintCount + tiers[_tier - 1].maxSupply;
        }
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
    function setTierData(uint8 _tier, uint128 _costWei) external onlyAdmin {
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
