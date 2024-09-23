// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PriceProvider} from "../../src/oracle/PriceProvider.sol";
import {IAggregatorV3} from "../../src/interfaces/IAggregatorV3.sol";
import {IWeETH} from "../../src/interfaces/IWeETH.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";


contract PriceProviderTest is Test {
    PriceProvider priceProvider;
    address owner = makeAddr("owner");

    address weETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address btc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address matic = 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0;

    address weETHOracle = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address btcEthOracle = 0xdeb288F737066589598e9214E782fa5A8eD689e8;
    address ethUsdOracle = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address maticUsdOracle = 0x7bAC85A8a13A4BcD8abb3eB7d6b4d632c5a57676;

    PriceProvider.Config weETHConfig;
    PriceProvider.Config btcConfig;
    PriceProvider.Config ethConfig;
    PriceProvider.Config maticConfig;
    function setUp() public {
        string memory mainnet = "https://eth-pokt.nodies.app";
        vm.createSelectFork(mainnet);

        vm.startPrank(owner);
        weETHConfig = PriceProvider.Config({
            oracle: weETHOracle,
            priceFunctionCalldata: abi.encodeWithSelector(
                IWeETH.getEETHByWeETH.selector,
                1000000000000000000
            ),
            isChainlinkType: false,
            oraclePriceDecimals: 18,
            maxStaleness: 0,
            dataType: PriceProvider.ReturnType.Uint256,
            isBaseTokenEth: true
        });

        btcConfig = PriceProvider.Config({
            oracle: btcEthOracle,
            priceFunctionCalldata: hex"",
            isChainlinkType: true,
            oraclePriceDecimals: IAggregatorV3(btcEthOracle).decimals(),
            maxStaleness: 1 days,
            dataType: PriceProvider.ReturnType.Int256,
            isBaseTokenEth: true
        });

        ethConfig = PriceProvider.Config({
            oracle: ethUsdOracle,
            priceFunctionCalldata: hex"",
            isChainlinkType: true,
            oraclePriceDecimals: IAggregatorV3(ethUsdOracle).decimals(),
            maxStaleness: 1 days,
            dataType: PriceProvider.ReturnType.Int256,
            isBaseTokenEth: false
        });

        maticConfig = PriceProvider.Config({
            oracle: maticUsdOracle,
            priceFunctionCalldata: hex"",
            isChainlinkType: true,
            oraclePriceDecimals: IAggregatorV3(maticUsdOracle).decimals(),
            maxStaleness: 1 days,
            dataType: PriceProvider.ReturnType.Int256,
            isBaseTokenEth: false
        });

        address[] memory initialTokens = new address[](3);
        initialTokens[0] = weETH;
        initialTokens[1] = btc;
        initialTokens[2] = eth;

        PriceProvider.Config[]
            memory initialTokensConfig = new PriceProvider.Config[](3);
        initialTokensConfig[0] = weETHConfig;
        initialTokensConfig[1] = btcConfig;
        initialTokensConfig[2] = ethConfig;

        priceProvider = new PriceProvider(
            owner,
            initialTokens,
            initialTokensConfig
        );

        vm.stopPrank();
    }

    function test_ExchangeRatePrice() public view {
        uint256 priceOfWeETH = IWeETH(weETH).getEETHByWeETH(1 ether);
        (, int256 ans, , , ) = IAggregatorV3(ethUsdOracle).latestRoundData();
        uint256 oracleDecimals = IAggregatorV3(ethUsdOracle).decimals();
        uint256 price = (priceOfWeETH * uint256(ans) * 10 ** priceProvider.decimals()) / 10 ** (18 + oracleDecimals);
        assertEq(priceProvider.price(weETH), price);
    }

    function test_CanAddNewOracle() public {
        address[] memory tokens = new address[](1);
        tokens[0] = matic;

        PriceProvider.Config[] memory tokensConfig = new PriceProvider.Config[](1);
        tokensConfig[0] = maticConfig;

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit PriceProvider.TokenConfigSet(tokens, tokensConfig);
        priceProvider.setTokenConfig(tokens, tokensConfig);

        (, int256 ans, , , ) = IAggregatorV3(maticUsdOracle).latestRoundData();
        uint256 oracleDecimals = IAggregatorV3(maticUsdOracle).decimals();
        uint256 expectedPrice = uint256(ans) * 10 ** priceProvider.decimals() / 10 ** oracleDecimals;
        assertEq(priceProvider.price(matic), expectedPrice);
    }

    function test_OnlyOwnerCanAddNewOracle() public {
        address[] memory tokens = new address[](1);
        tokens[0] = matic;

        PriceProvider.Config[] memory tokensConfig = new PriceProvider.Config[](1);
        tokensConfig[0] = maticConfig;

        address notOwner = makeAddr("notOwner");

        vm.startPrank(notOwner);
        vm.expectRevert(buildAccessControlRevertData(notOwner, priceProvider.ADMIN_ROLE()));
        priceProvider.setTokenConfig(tokens, tokensConfig);
        vm.stopPrank();
    }

    function test_CannotAddNewOracleIfArrayLengthMismatch() public {
        address[] memory tokens = new address[](2);
        tokens[0] = matic;

        PriceProvider.Config[] memory tokensConfig = new PriceProvider.Config[](1);
        tokensConfig[0] = maticConfig;

        vm.startPrank(owner);
        vm.expectRevert(PriceProvider.ArrayLengthMismatch.selector);
        priceProvider.setTokenConfig(tokens, tokensConfig);
        vm.stopPrank();
    }

    function test_BtcOracle() public view {
        (, int256 btcAns, , , ) = IAggregatorV3(btcEthOracle).latestRoundData();
        uint256 btcOracleDecimals = IAggregatorV3(btcEthOracle).decimals();

        (, int256 ethAns, , , ) = IAggregatorV3(ethUsdOracle).latestRoundData();
        uint256 ethOracleDecimals = IAggregatorV3(ethUsdOracle).decimals();

        uint256 finalPrice = 
            (uint256(btcAns) * uint256(ethAns) * 10 ** priceProvider.decimals()) /
            10 ** (btcOracleDecimals + ethOracleDecimals);
        assertEq(priceProvider.price(btc), finalPrice);
    }

    function test_MaticUsdOracle() public {
        address[] memory tokens = new address[](1);
        tokens[0] = matic;

        PriceProvider.Config[] memory tokensConfig = new PriceProvider.Config[](1);
        tokensConfig[0] = maticConfig;

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit PriceProvider.TokenConfigSet(tokens, tokensConfig);
        priceProvider.setTokenConfig(tokens, tokensConfig);

        (, int256 maticAns, , , ) = IAggregatorV3(maticUsdOracle)
            .latestRoundData();
        uint256 maticPrice = uint256(maticAns);
        uint256 maticOracleDecimals = IAggregatorV3(maticUsdOracle).decimals();

        uint256 finalPrice = (maticPrice * 10 ** priceProvider.decimals()) / 10 ** maticOracleDecimals;

        assertEq(priceProvider.price(matic), finalPrice);
    }

    function buildAccessControlRevertData(
        address account,
        bytes32 role
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                account,
                role
            );
    }
}