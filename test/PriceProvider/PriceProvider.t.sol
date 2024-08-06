// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console, stdError} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PriceProvider} from "../../src/oracle/PriceProvider.sol";

contract PriceProviderTest is Test {
    address owner = makeAddr("owner");
    PriceProvider priceProvider;

    address weEthWethOracle = 0xE141425bc1594b8039De6390db1cDaf4397EA22b;
    address ethUsdcOracle = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;

    function setUp() public {
        vm.createSelectFork("https://rpc.ankr.com/arbitrum");
        priceProvider = new PriceProvider(weEthWethOracle, ethUsdcOracle);

        vm.stopPrank();
    }

    function test_Value() public view {
        console.log(priceProvider.getWeEthUsdPrice());
    }
}
