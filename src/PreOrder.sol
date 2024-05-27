// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";

contract PreorderContract is
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    // Amount require for each tier
    uint256 public lowTierAmount;
    uint256 public mediumTierAmount;
    uint256 public premiumTierAmount;

    // ETH and EETH can be used as payment
    IERC20 public eethToken;

    // Gnosis Safe to receive the preorder payments
    address payable public gnosisSafe;

    // Contract owner is the timelock, admin role needed to preform timely actions on the contract
    address public admin;

    enum Tier { Unknown, Low, Medium, Premium }

    event Preorder(address indexed user, Tier tier, uint256 amount);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address initialOwner,
        address payable _gnosisSafe, 
        uint256 _lowTierAmount, 
        uint256 _mediumTierAmount, 
        uint256 _premiumTierAmount,
        IERC20 _eethToken
    ) external initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        
        gnosisSafe = _gnosisSafe;
        lowTierAmount = _lowTierAmount;
        mediumTierAmount = _mediumTierAmount;
        premiumTierAmount = _premiumTierAmount;
        eethToken = _eethToken;
    }

    //--------------------------------------------------------------------------------------
    //--------------------------------  Public ---------------------------------------------
    //--------------------------------------------------------------------------------------

    function preorder(Tier tier) external payable {
        uint256 amount = getTierAmount(tier);
        require(msg.value == amount, "Incorrect amount");
        (bool success, ) = gnosisSafe.call{value: msg.value}("");
        require(success, "Transfer failed");

        emit Preorder(msg.sender, tier, msg.value);
    }

    function preorderWithPermit(
        Tier tier,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        uint256 amount = getTierAmount(tier);
        require(value == amount, "Incorrect amount");
        IERC20Permit(address(eethToken)).permit(msg.sender, address(this), value, deadline, v, r, s);
        require(eethToken.transferFrom(msg.sender, gnosisSafe, value), "Transfer failed");

        emit Preorder(msg.sender, tier, value);
    }

    function getTierAmount(Tier tier) public view returns (uint256) {
        if (tier == Tier.Low) {
            return lowTierAmount;
        } else if (tier == Tier.Medium) {
            return mediumTierAmount;
        } else if (tier == Tier.Premium) {
            return premiumTierAmount;
        } else {
            revert("Invalid tier");
        }
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  Admin  -------------------------------------------
    //--------------------------------------------------------------------------------------

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
