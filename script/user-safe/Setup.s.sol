// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {UserSafeFactory} from "../../src/user-safe/UserSafeFactory.sol";
import {UserSafe} from "../../src/user-safe/UserSafe.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PriceProvider} from "../../src/oracle/PriceProvider.sol";
import {Swapper1InchV6} from "../../src/utils/Swapper1InchV6.sol";
import {IL2DebtManager, L2DebtManager} from "../../src/L2DebtManager.sol";
import {CashDataProvider} from "../../src/utils/CashDataProvider.sol";
import {Utils, ChainConfig} from "./Utils.sol";
import {EtherFiCashAaveV3Adapter} from "../../src/adapters/aave-v3/EtherFiCashAaveV3Adapter.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";

contract DeployUserSafeSetup is Utils {
    ERC20 usdc;
    ERC20 weETH;
    PriceProvider priceProvider;
    Swapper1InchV6 swapper;
    UserSafe userSafeImpl;
    UserSafeFactory userSafeFactory;
    L2DebtManager debtManager;
    CashDataProvider cashDataProvider;
    EtherFiCashAaveV3Adapter aaveV3Adapter;
    address etherFiCashMultisig;
    address etherFiWallet;
    address owner;
    uint256 delay = 300; // 5 min
    uint256 ltv = 70e18;

    uint256 liquidationThreshold = 60e18; // 60%
    uint256 borrowApyPerSecond = 634195839675; // 20% APR -> 20e18 / (365 days in seconds)

    // Shivam Metamask wallets
    address recoverySigner1 = 0x7fEd99d0aA90423de55e238Eb5F9416FF7Cc58eF;
    address recoverySigner2 = 0x24e311DA50784Cf9DB1abE59725e4A1A110220FA;
    string chainId;
    uint16 aaveV3ReferralCode = 0;
    uint256 interestRateMode = 2; // variable

    function run() public {
        // Pulling deployer info from the environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        // Start broadcast with deployer as the signer
        vm.startBroadcast(deployerPrivateKey);

        chainId = vm.toString(block.chainid);
        ChainConfig memory chainConfig = getChainConfig(chainId);

        address[] memory supportedCollateralTokens = new address[](1);
        supportedCollateralTokens[0] = chainConfig.weETH;
        address[] memory supportedBorrowTokens = new address[](1);
        supportedBorrowTokens[0] = chainConfig.usdc;

        etherFiWallet = deployerAddress;
        etherFiCashMultisig = deployerAddress;
        owner = deployerAddress;

        usdc = ERC20(chainConfig.usdc);
        weETH = ERC20(chainConfig.weETH);
        priceProvider = new PriceProvider(
            chainConfig.weETH,
            chainConfig.weEthWethOracle,
            chainConfig.ethUsdcOracle
        );
        swapper = new Swapper1InchV6(
            chainConfig.swapRouter1InchV6,
            supportedCollateralTokens
        );
        aaveV3Adapter = new EtherFiCashAaveV3Adapter(
            chainConfig.aaveV3Pool,
            chainConfig.aaveV3PoolDataProvider,
            aaveV3ReferralCode,
            interestRateMode
        );

        address cashDataProviderImpl = address(new CashDataProvider());
        cashDataProvider = CashDataProvider(
            address(new UUPSProxy(cashDataProviderImpl, ""))
        );

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = address(weETH);
        address[] memory borrowTokens = new address[](1);
        borrowTokens[0] = address(usdc);

        IL2DebtManager.CollateralTokenConfigData[]
            memory collateralTokenConfig = new IL2DebtManager.CollateralTokenConfigData[](
                1
            );
        collateralTokenConfig[0] = IL2DebtManager.CollateralTokenConfigData({
            ltv: ltv,
            liquidationThreshold: liquidationThreshold
        });
        uint256[] memory borrowApys = new uint256[](1);
        borrowApys[0] = borrowApyPerSecond;

        address debtManagerImpl = address(
            new L2DebtManager(address(cashDataProvider))
        );

        debtManager = L2DebtManager(
            address(new UUPSProxy(debtManagerImpl, ""))
        );

        CashDataProvider(address(cashDataProvider)).initialize(
            owner,
            uint64(delay),
            etherFiWallet,
            etherFiCashMultisig,
            address(debtManager),
            address(usdc),
            address(weETH),
            address(priceProvider),
            address(swapper),
            address(aaveV3Adapter)
        );

        debtManager.initialize(
            owner,
            uint48(delay),
            collateralTokens,
            collateralTokenConfig,
            borrowTokens,
            borrowApys
        );
        userSafeImpl = new UserSafe(
            address(cashDataProvider),
            recoverySigner1,
            recoverySigner2
        );

        userSafeFactory = new UserSafeFactory(address(userSafeImpl), owner);

        string memory parentObject = "parent object";

        string memory deployedAddresses = "addresses";

        vm.serializeAddress(deployedAddresses, "usdc", address(usdc));

        vm.serializeAddress(deployedAddresses, "weETH", address(weETH));
        vm.serializeAddress(
            deployedAddresses,
            "priceProvider",
            address(priceProvider)
        );
        vm.serializeAddress(deployedAddresses, "swapper", address(swapper));
        vm.serializeAddress(
            deployedAddresses,
            "userSafeImpl",
            address(userSafeImpl)
        );
        vm.serializeAddress(
            deployedAddresses,
            "userSafeFactory",
            address(userSafeFactory)
        );
        vm.serializeAddress(
            deployedAddresses,
            "debtManagerProxy",
            address(debtManager)
        );
        vm.serializeAddress(
            deployedAddresses,
            "debtManagerImpl",
            address(debtManagerImpl)
        );
        vm.serializeAddress(
            deployedAddresses,
            "cashDataProviderProxy",
            address(cashDataProvider)
        );
        vm.serializeAddress(
            deployedAddresses,
            "cashDataProviderImpl",
            address(cashDataProviderImpl)
        );
        vm.serializeAddress(
            deployedAddresses,
            "etherFiCashMultisig",
            address(etherFiCashMultisig)
        );
        vm.serializeAddress(
            deployedAddresses,
            "etherFiWallet",
            address(etherFiWallet)
        );
        vm.serializeAddress(deployedAddresses, "owner", address(owner));
        vm.serializeAddress(
            deployedAddresses,
            "recoverySigner1",
            address(recoverySigner1)
        );

        string memory addressOutput = vm.serializeAddress(
            deployedAddresses,
            "recoverySigner2",
            address(recoverySigner2)
        );

        // serialize all the data
        string memory finalJson = vm.serializeString(
            parentObject,
            deployedAddresses,
            addressOutput
        );

        writeDeploymentFile(finalJson);

        vm.stopBroadcast();
    }
}
