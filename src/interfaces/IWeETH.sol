// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IWeETH {
    function getEETHByWeETH(
        uint256 _weETHAmount
    ) external view returns (uint256);
}