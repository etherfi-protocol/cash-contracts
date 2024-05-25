// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

contract PreorderContract is 
    Initializable, 
    OwnableUpgradeable,
    UUPSUpgradeable
{
    address payable public gnosisSafe;
    uint256 public lowTierAmount;
    uint256 public mediumTierAmount;
    uint256 public premiumTierAmount;

    event Preorder(address indexed user, string tier, uint256 amount);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address initialOwner,
        address payable _gnosisSafe, 
        uint256 _lowTierAmount, 
        uint256 _mediumTierAmount, 
        uint256 _premiumTierAmount
    ) public initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        gnosisSafe = _gnosisSafe;
        lowTierAmount = _lowTierAmount;
        mediumTierAmount = _mediumTierAmount;
        premiumTierAmount = _premiumTierAmount;
    }

    function preorderLowTier() external payable {
        require(msg.value == lowTierAmount, "Incorrect amount");
        _sendFunds(msg.value);
        emit Preorder(msg.sender, "LowTier", msg.value);
    }

    function preorderMediumTier() external payable {
        require(msg.value == mediumTierAmount, "Incorrect amount");
        _sendFunds(msg.value);
        emit Preorder(msg.sender, "MediumTier", msg.value);
    }

    function preorderPremiumTier() external payable {
        require(msg.value == premiumTierAmount, "Incorrect amount");
        _sendFunds(msg.value);
        emit Preorder(msg.sender, "PremiumTier", msg.value);
    }

    function _sendFunds(uint256 amount) internal {
        (bool success, ) = gnosisSafe.call{value: amount}("");
        require(success, "Transfer failed");
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    receive() external payable {
        revert("Direct transfers not allowed");
    }
}