// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "./custom1155.sol";

contract PreOrder is
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    CustomERC1155
{
    // Gnosis Safe to receive the preorder payments
    address payable public gnosisSafe;
    address public fiatMinter;

    // Storages the data for each tier
    // Number of tiers is configurable upon initialization
    //  * - tiers[0] -> TierData for Tier 0
    //  * - tiers[1] -> TierData for Tier 1
    //  ....
    //  * - tiers[n] -> TierData for Tier n
    mapping(uint8 => TierData) public tiers;

    // Configurable parameters for each tier
    struct TierConfig {
        uint128 costWei;
        uint32 maxSupply;
    }

    // Store the metaData for each tier
    struct TierData {
        // cost in wei to mint a token of this tier
        uint128 costWei;
        // max supply of tokens for this tier
        uint32 maxSupply;
        // number of tokens minted for this tier
        uint32 mintCount;
        // starting id for this tier
        uint32 startId;
    }

    enum Type {
        PRE_ORDER,
        CRYPTO_ORDER,
        FIAT_ORDER
    }

    // Contract owner is the timelock, admin role needed to eeform timely actions on the contract
    address public admin;

    // eETH can also be used as a payment
    address public eEthToken;

    // NFT metadata storage location
    string public baseURI;

    // Pre Order cutoff block
    uint256 public preOrderCutoffBlockNumber;

    // Event emitted when a PreOrder is processed
    event PreOrderMint(
        address indexed buyer,
        uint256 indexed tier,
        uint256 amount,
        uint256 tokenId
    );

    // Event emitted when a Order is processed
    event OrderCryptoMint(
        address indexed buyer,
        uint256 indexed tier,
        uint256 amount,
        uint256 tokenId
    );

    // Event emitted when a Order is placed via Apple/Google
    event OrderFiatMint(
        address indexed buyer,
        uint256 indexed tier,
        uint256 amount,
        uint256 tokenId
    );

    function initialize(
        address initialOwner,
        address _gnosisSafe,
        address _admin,
        address _eEthToken,
        string memory _baseURI,
        TierConfig[] memory tierConfigArray,
        uint256 _preOrderCutoffBlockNumber,
        address _fiatMinter
    ) public initializer {
        require(
            initialOwner != address(0),
            "Incorrect address for initialOwner"
        );
        require(_gnosisSafe != address(0), "Incorrect address for gnosisSafe");
        require(_admin != address(0), "Incorrect address for admin");
        require(_eEthToken != address(0), "Incorrect address for eEthToken");

        __Ownable_init(initialOwner);
        __Pausable_init();

        gnosisSafe = payable(_gnosisSafe);
        fiatMinter = _fiatMinter;
        admin = _admin;
        eEthToken = _eEthToken;
        baseURI = _baseURI;
        preOrderCutoffBlockNumber = _cutoffBlockNumber;

        uint32 totalCards = 0;
        for (uint8 i = 0; i < tierConfigArray.length; i++) {
            tiers[i] = TierData({
                costWei: tierConfigArray[i].costWei,
                maxSupply: tierConfigArray[i].maxSupply,
                mintCount: 0,
                startId: totalCards
            });

            totalCards += tierConfigArray[i].maxSupply;
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
    function mint(uint8 _tier, uint8 _type, address _buyer) external payable whenNotPaused {
        require(
            tiers[_tier].mintCount < tiers[_tier].maxSupply,
            "Tier sold out"
        );

        uint256 tokenId = tiers[_tier].startId + tiers[_tier].mintCount;
        tiers[_tier].mintCount += 1;

        if (_type != uint8(Type.FIAT_ORDER)){
            require(msg.value == tiers[_tier].costWei, "Incorrect amount sent");
            (bool success, ) = gnosisSafe.call{value: msg.value}("");
            require(success, "Transfer failed");
            if (_type == uint8(Type.PRE_ORDER)) {
                emit PreOrderMint(_buyer, _tier, _amount, tokenId);
            }
            if (_type == uint8(Type.CRYPTO_ORDER)) {
                emit OrderCryptoMint(_buyer, _tier, _amount, tokenId);
            }
        } else {
            require(msg.sender == fiatMinter, "Not the fiatMinter");
            emit OrderFiatMint(_buyer, _tier, _amount, tokenId);
        }

        safeMint(_buyer, _tier, tokenId);
    }

    // Mints a token with eETH as payment
    function MintWithPermit(
        uint8 _tier,
        uint256 _amount,
        uint256 _deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external whenNotPaused {
        require(_amount == tiers[_tier].costWei, "Incorrect amount sent");
        require(
            tiers[_tier].mintCount < tiers[_tier].maxSupply,
            "Tier sold out"
        );

        IERC20Permit(eEthToken).permit(
            msg.sender,
            address(this),
            _amount,
            _deadline,
            v,
            r,
            s
        );
        IERC20(eEthToken).transferFrom(msg.sender, gnosisSafe, _amount);

        uint256 tokenId = tiers[_tier].startId + tiers[_tier].mintCount;
        tiers[_tier].mintCount += 1;

        safeMint(msg.sender, _tier, tokenId);

        emit PreOrderMint(msg.sender, _tier, _amount, tokenId);
    }

    function maxSupply() external view returns (uint256) {
        return tokens.length;
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

    // Sets the uri
    function setURI(string memory _uri) external onlyAdmin {
        baseURI = _uri;
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

    // Updates the fiatMinter
    function setFiatMinter(address _fiatMinter) external onlyAdmin {
        fiatMinter = _fiatMinter;
    }

    // Restricts the ability to upgrade the contract to the owner
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

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
