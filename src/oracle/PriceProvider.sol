// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPriceProvider} from "../interfaces/IPriceProvider.sol";
import {IAggregatorV3} from "../interfaces/IAggregatorV3.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {UUPSUpgradeable, Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

contract PriceProvider is IPriceProvider, Initializable, UUPSUpgradeable, AccessControlDefaultAdminRulesUpgradeable {
    using Math for uint256;

    enum ReturnType {
        Int256,
        Uint256
    }

    struct Config {
        address oracle;
        bytes priceFunctionCalldata;
        bool isChainlinkType;
        uint8 oraclePriceDecimals;
        uint24 maxStaleness;
        ReturnType dataType;
        bool isBaseTokenEth;
        bool isStableToken;
    }

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    // ETH to USD price
    address public constant ETH_USD_ORACLE_SELECTOR =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    // WETH to USD price
    address public constant WETH_USD_ORACLE_SELECTOR =
        0x5300000000000000000000000000000000000004;
    
    uint8 public constant DECIMALS = 6;
    uint256 public constant STABLE_PRICE = 10 ** DECIMALS;
    uint256 public constant MAX_STABLE_DEVIATION = STABLE_PRICE / 100; // 1%

    mapping(address token => Config tokenConfig) public tokenConfig;

    event TokenConfigSet(address[] tokens, Config[] configs);

    error TokenOracleNotSet();
    error PriceOracleFailed();
    error InvalidPrice();
    error OraclePriceTooOld();
    error ArrayLengthMismatch();
    error StablePriceCannotBeZero();

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address __owner,
        address[] memory __tokens,
        Config[] memory __configs
    ) external initializer {
        __AccessControlDefaultAdminRules_init_unchained(5 * 60, __owner);
        _setTokenConfig(__tokens, __configs);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function setTokenConfig(address[] memory _tokens, Config[] memory _configs) external onlyRole(ADMIN_ROLE) {
        _setTokenConfig(_tokens, _configs);
    }

    function price(address token) external view returns (uint256) {
        if (token == ETH_USD_ORACLE_SELECTOR || token == WETH_USD_ORACLE_SELECTOR) {
            (uint256 ethUsdPrice, uint8 ethPriceDecimals) = _getEthUsdPrice();
            return ethUsdPrice.mulDiv(10 ** decimals(), 10 ** ethPriceDecimals, Math.Rounding.Floor);
        }

        (uint256 tokenPrice, bool isBaseEth, uint8 priceDecimals) = _getPrice(token);

        if (isBaseEth) {
            (uint256 ethUsdPrice, uint8 ethPriceDecimals) = _getEthUsdPrice();
            return tokenPrice.mulDiv(ethUsdPrice * 10 ** decimals(), 10 ** (ethPriceDecimals + priceDecimals), Math.Rounding.Floor);
        }

        return tokenPrice.mulDiv(10 ** decimals(), 10 ** priceDecimals, Math.Rounding.Floor);
    }

    function _getEthUsdPrice() internal view returns (uint256, uint8) {
        (uint256 tokenPrice, , uint8 priceDecimals) = _getPrice(ETH_USD_ORACLE_SELECTOR);
        return (tokenPrice, priceDecimals);
    }

    function decimals() public pure returns (uint8) {
        return DECIMALS;
    }

    function _getPrice(
        address token
    ) internal view returns (uint256, bool, uint8) {
        Config memory config = tokenConfig[token];
        if (config.oracle == address(0)) revert TokenOracleNotSet();
        uint256 tokenPrice;

        if (config.isChainlinkType) {
            (, int256 priceInt256, , uint256 updatedAt, ) = IAggregatorV3(config.oracle).latestRoundData();
            if (block.timestamp > updatedAt + config.maxStaleness) revert OraclePriceTooOld();
            if (priceInt256 <= 0) revert InvalidPrice();
            tokenPrice = uint256(priceInt256);
            if (config.isStableToken) return (_getStablePrice(tokenPrice, config.oraclePriceDecimals), false, decimals());
            return (tokenPrice, config.isBaseTokenEth, config.oraclePriceDecimals);
        }

        (bool success, bytes memory data) = address(config.oracle).staticcall(config.priceFunctionCalldata);
        if (!success) revert PriceOracleFailed();

        if (config.dataType == ReturnType.Int256) {
            int256 priceInt256 = abi.decode(data, (int256));
            if (priceInt256 <= 0) revert InvalidPrice();
            tokenPrice = uint256(priceInt256);
        } else tokenPrice = abi.decode(data, (uint256));

        if (config.isStableToken) return (_getStablePrice(tokenPrice, config.oraclePriceDecimals), false, decimals());
        return (tokenPrice, config.isBaseTokenEth, config.oraclePriceDecimals);
    }

    function _getStablePrice(uint256 _price, uint8 oracleDecimals) internal pure returns (uint256) {    
        _price = _price.mulDiv(10 ** decimals(), 10 ** oracleDecimals);  
        if (_price == 0) revert StablePriceCannotBeZero();

        if (
            uint256(_price) > STABLE_PRICE - MAX_STABLE_DEVIATION &&
            uint256(_price) < STABLE_PRICE + MAX_STABLE_DEVIATION
        ) return STABLE_PRICE;
        else return _price;
    }

    function _setTokenConfig(
        address[] memory _tokens,
        Config[] memory _configs
    ) internal {
        uint256 len = _tokens.length;
        if(len != _configs.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < len; ) {
            tokenConfig[_tokens[i]] = _configs[i];
            unchecked {
                ++i;
            }
        }

        emit TokenConfigSet(_tokens, _configs);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
