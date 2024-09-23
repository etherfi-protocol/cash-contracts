// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {UUPSUpgradeable, Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IL2DebtManager} from "../interfaces/IL2DebtManager.sol";
import {IPriceProvider} from "../interfaces/IPriceProvider.sol";
import {IEtherFiCashAaveV3Adapter} from "../interfaces/IEtherFiCashAaveV3Adapter.sol";
import {ICashDataProvider} from "../interfaces/ICashDataProvider.sol";
import {AaveLib} from "../libraries/AaveLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuardTransientUpgradeable} from "../utils/ReentrancyGuardTransientUpgradeable.sol";

/**
 * @title L2 Debt Manager
 * @author @seongyun-ko @shivam-ef
 * @notice Contract to manage lending and borrowing for Cash protocol
 */
contract DebtManagerStorage is
    Initializable,
    UUPSUpgradeable,
    AccessControlDefaultAdminRulesUpgradeable,
    ReentrancyGuardTransientUpgradeable
{
    using Math for uint256;
    enum MarketOperationType {
        Supply,
        Borrow,
        Repay,
        Withdraw,
        SupplyAndBorrow
    }

    struct BorrowTokenConfigData {
        uint64 borrowApy;
        uint128 minShares;
    }

    struct BorrowTokenConfig {
        uint256 interestIndexSnapshot;
        uint256 totalBorrowingAmount;
        uint256 totalSharesOfBorrowTokens;
        uint64 lastUpdateTimestamp;
        uint64 borrowApy;
        uint128 minShares;
    }

    struct CollateralTokenConfig {
        uint80 ltv;
        uint80 liquidationThreshold;
        uint96 liquidationBonus;
        uint256 supplyCap;
    }

    struct TokenData {
        address token;
        uint256 amount;
    }

    struct LiquidationTokenData {
        address token;
        uint256 amount;
        uint256 liquidationBonus;
    }

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint256 public constant HUNDRED_PERCENT = 100e18;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant SIX_DECIMALS = 1e6;

    ICashDataProvider internal _cashDataProvider;

    address[] internal _supportedCollateralTokens;
    address[] internal _supportedBorrowTokens;
    mapping(address token => uint256 index) internal _collateralTokenIndexPlusOne;
    mapping(address token => uint256 index) internal _borrowTokenIndexPlusOne;
    mapping(address borrowToken => BorrowTokenConfig config) internal _borrowTokenConfig;

    // Collateral held by the user
    mapping(address user => mapping(address token => uint256 amount)) internal _userCollateral;
    // Total collateral held by the users with the contract
    mapping(address token => uint256 amount) internal _totalCollateralAmounts;
    mapping(address token => CollateralTokenConfig config)
        internal _collateralTokenConfig;

    // Borrowings is in USD with 6 decimals
    mapping(address user => mapping(address borrowToken => uint256 borrowing))
        internal _userBorrowings;
    // Snapshot of user's interests already paid
    mapping(address user => mapping(address borrowToken => uint256 interestSnapshot))
        internal _usersDebtInterestIndexSnapshots;

    // Shares have 18 decimals
    mapping(address supplier => mapping(address borrowToken => uint256 shares)) internal _sharesOfBorrowTokens;
    
    //keccak256("DebtManager.admin.impl");
    bytes32 constant adminImplPosition =
        0x49d4a010ddc5f453173525f0adf6cfb97318b551312f237c11fd9f432a1f5d21;

    address internal _cashTokenWrapperFactory;


    event SuppliedUSDC(uint256 amount);
    event DepositedCollateral(
        address indexed depositor,
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event Supplied(
        address indexed sender,
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event Borrowed(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event Repaid(
        address indexed user,
        address indexed payer,
        address indexed token,
        uint256 amount
    );
    event RepaidWithCollateralToken(
        address indexed user,
        address indexed payer,
        address indexed collateralToken,
        uint256 beforeCollateralAmount,
        uint256 afterCollateralAmount,
        uint256 repaidUsdcDebtAmount
    );
    event RepaidWithCollateral(
        address indexed user,
        uint256 repaidUsdcDebtAmount,
        TokenData[] collateralUsed
    );
    event Liquidated(
        address indexed liquidator,
        address indexed user,
        address indexed debtTokenToLiquidate,
        TokenData[] beforeCollateralAmount,
        LiquidationTokenData[] userCollateralLiquidated,
        uint256 beforeDebtAmount,
        uint256 debtAmountLiquidated
    );
    event LiquidationThresholdUpdated(
        uint256 oldThreshold,
        uint256 newThreshold
    );
    event CollateralTokenAdded(address token);
    event CollateralTokenRemoved(address token);
    event BorrowTokenAdded(address token);
    event BorrowTokenRemoved(address token);
    event BorrowApySet(address indexed token, uint256 oldApy, uint256 newApy);
    event MinSharesOfBorrowTokenSet(address indexed token, uint128 oldMinShares, uint128 newMinShares);
    event UserInterestAdded(
        address indexed user,
        uint256 borrowingAmtBeforeInterest,
        uint256 borrowingAmtAfterInterest
    );
    event TotalBorrowingUpdated(
        address indexed borrowToken,
        uint256 totalBorrowingAmtBeforeInterest,
        uint256 totalBorrowingAmtAfterInterest
    );
    event WithdrawCollateral(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event AccountClosed(address indexed user, TokenData[] collateralWithdrawal);
    event BorrowTokenConfigSet(address indexed token, BorrowTokenConfig config);
    event CollateralTokenConfigSet(
        address indexed collateralToken,
        CollateralTokenConfig oldConfig,
        CollateralTokenConfig newConfig
    );
    event WithdrawBorrowToken(
        address indexed withdrawer,
        address indexed borrowToken,
        uint256 amount
    );

    error UnsupportedCollateralToken();
    error UnsupportedRepayToken();
    error UnsupportedBorrowToken();
    error InsufficientCollateral();
    error InsufficientCollateralToRepay();
    error InsufficientLiquidity();
    error CannotLiquidateYet();
    error ZeroCollateralValue();
    error OnlyUserCanRepayWithCollateral();
    error InvalidValue();
    error AlreadyCollateralToken();
    error AlreadyBorrowToken();
    error NotACollateralToken();
    error NoCollateralTokenLeft();
    error NotABorrowToken();
    error NoBorrowTokenLeft();
    error ArrayLengthMismatch();
    error TotalCollateralAmountNotZero();
    error InsufficientLiquidityPleaseTryAgainLater();
    error LiquidAmountLesserThanRequired();
    error ZeroTotalBorrowTokens();
    error InsufficientBorrowShares();
    error UserStillLiquidatable();
    error TotalBorrowingsForUserNotZero();
    error BorrowTokenConfigAlreadySet();
    error AccountUnhealthy();
    error BorrowTokenStillInTheSystem();
    error RepaymentAmountIsZero();
    error LiquidatableAmountIsZero();
    error LtvCannotBeGreaterThanLiquidationThreshold();
    error OraclePriceZero();
    error BorrowAmountZero();
    error SharesCannotBeZero();
    error SharesCannotBeLessThanMinShares();
    error SupplyCapBreached();
    error OnlyUserSafe();
    error TokenWrapperContractNotFound();
    error AaveAdapterNotSet();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice set the implementation for the admin, this needs to be in a base class else we cannot set it
     * @param newImpl address of the implementation
     */
    function setAdminImpl(address newImpl) external onlyRole(ADMIN_ROLE) {
        bytes32 position = adminImplPosition;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(position, newImpl)
        }
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function _getTotalBorrowTokenAmount(
        address borrowToken
    ) internal view returns (uint256) {
        return
            _convertFromSixDecimals(borrowToken, totalBorrowingAmount(borrowToken)) +
            IERC20(borrowToken).balanceOf(address(this));
    }

    function totalBorrowingAmount(
        address borrowToken
    ) public view returns (uint256) {
        return
            _getAmountWithInterest(
                borrowToken,
                _borrowTokenConfig[borrowToken].totalBorrowingAmount,
                _borrowTokenConfig[borrowToken].interestIndexSnapshot
            );
    }

    function _getAmountWithInterest(
        address borrowToken,
        uint256 amountBefore,
        uint256 accInterestAlreadyAdded
    ) internal view returns (uint256) {
        return
            ((PRECISION *
                (amountBefore *
                    (debtInterestIndexSnapshot(borrowToken) -
                        accInterestAlreadyAdded))) /
                HUNDRED_PERCENT +
                PRECISION *
                amountBefore) / PRECISION;
    }

    function debtInterestIndexSnapshot(
        address borrowToken
    ) public view returns (uint256) {
        return
            _borrowTokenConfig[borrowToken].interestIndexSnapshot +
            (block.timestamp -
                _borrowTokenConfig[borrowToken].lastUpdateTimestamp) *
            _borrowTokenConfig[borrowToken].borrowApy;
    }

        function _updateBorrowings(address user) internal {
        uint256 len = _supportedBorrowTokens.length;
        for (uint256 i = 0; i < len; ) {
            _updateBorrowings(user, _supportedBorrowTokens[i]);
            unchecked {
                ++i;
            }
        }
    }

    function _updateBorrowings(address user, address borrowToken) internal {
        uint256 totalBorrowingAmtBeforeInterest = _borrowTokenConfig[
            borrowToken
        ].totalBorrowingAmount;

        _borrowTokenConfig[borrowToken]
            .interestIndexSnapshot = debtInterestIndexSnapshot(borrowToken);
        _borrowTokenConfig[borrowToken]
            .totalBorrowingAmount = totalBorrowingAmount(borrowToken);
        _borrowTokenConfig[borrowToken].lastUpdateTimestamp = uint64(
            block.timestamp
        );

        if (
            totalBorrowingAmtBeforeInterest !=
            _borrowTokenConfig[borrowToken].totalBorrowingAmount
        )
            emit TotalBorrowingUpdated(
                borrowToken,
                totalBorrowingAmtBeforeInterest,
                _borrowTokenConfig[borrowToken].totalBorrowingAmount
            );

        if (user != address(0)) {
            uint256 userBorrowingsBefore = _userBorrowings[user][borrowToken];
            _userBorrowings[user][borrowToken] = borrowingOf(user, borrowToken);
            _usersDebtInterestIndexSnapshots[user][
                borrowToken
            ] = _borrowTokenConfig[borrowToken].interestIndexSnapshot;

            if (userBorrowingsBefore != _userBorrowings[user][borrowToken])
                emit UserInterestAdded(
                    user,
                    userBorrowingsBefore,
                    _userBorrowings[user][borrowToken]
                );
        }
    }

    function borrowingOf(
        address user
    ) public view returns (TokenData[] memory, uint256) {
        uint256 len = _supportedBorrowTokens.length;
        TokenData[] memory borrowTokenData = new TokenData[](len);
        uint256 totalBorrowingInUsd = 0;

        for (uint256 i = 0; i < len; ) {
            address borrowToken = _supportedBorrowTokens[i];
            uint256 amount = borrowingOf(user, borrowToken);
            totalBorrowingInUsd += amount;

            borrowTokenData[i] = TokenData({
                token: borrowToken,
                amount: amount
            });
            unchecked {
                ++i;
            }
        }

        return (borrowTokenData, totalBorrowingInUsd);
    }

    function borrowingOf(
        address user,
        address borrowToken
    ) public view returns (uint256) {
        return
            _getAmountWithInterest(
                borrowToken,
                _userBorrowings[user][borrowToken],
                _usersDebtInterestIndexSnapshots[user][borrowToken]
            );
    }

    function isCollateralToken(address token) public view returns (bool) {
        return _collateralTokenIndexPlusOne[token] != 0;
    }

    function isBorrowToken(address token) public view returns (bool) {
        return _borrowTokenIndexPlusOne[token] != 0;
    }

    function _convertToSixDecimals(
        address token,
        uint256 amount
    ) internal view returns (uint256) {
        uint8 tokenDecimals = _getDecimals(token);
        return
            tokenDecimals == 6
                ? amount
                : amount.mulDiv(SIX_DECIMALS, 10 ** tokenDecimals, Math.Rounding.Ceil);
    }

    function _convertFromSixDecimals(
        address token,
        uint256 amount
    ) internal view returns (uint256) {
        uint8 tokenDecimals = _getDecimals(token);
        return
            tokenDecimals == 6
                ? amount
                : amount.mulDiv(10 ** tokenDecimals, SIX_DECIMALS, Math.Rounding.Floor);
    }


    function _getDecimals(address token) internal view returns (uint8) {
        return IERC20Metadata(token).decimals();
    }
}