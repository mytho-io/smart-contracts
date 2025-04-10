// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console, console2, StdStyle} from "forge-std/Script.sol";

import {BurnMintTokenPool, TokenPool} from "@ccip/ccip/pools/BurnMintTokenPool.sol";
import {LockReleaseTokenPool} from "@ccip/ccip/pools/LockReleaseTokenPool.sol";
import {IBurnMintERC20} from "@ccip/shared/token/ERC20/IBurnMintERC20.sol";
import {RateLimiter} from "@ccip/ccip/libraries/RateLimiter.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {MYTHO} from "../src/MYTHO.sol";

import {IERC20} from "lib/ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

interface IRegistryModuleOwnerCustom {
    function registerAdminViaGetCCIPAdmin(address token) external;
    function registerAdminViaOwner(address token) external;
}

interface ITokenAdminRegistry {
    function acceptAdminRole(address localToken) external;
    function setPool(address localToken, address pool) external;
}


/**
 * @title MYTHO CCIP adjustemts between Soneium and Astar
 */
contract MythoCcipSetup is Script {
    LockReleaseTokenPool poolSoneium;
    BurnMintTokenPool poolAstar;
    MYTHO mythoSoneium;
    MYTHO mythoAstar;
    TransparentUpgradeableProxy proxySoneium;
    TransparentUpgradeableProxy proxyAstar;

    IRegistryModuleOwnerCustom registryModuleOwnerCustomAstar;
    IRegistryModuleOwnerCustom registryModuleOwnerCustomSoneium;

    ITokenAdminRegistry tokenAdminRegistryAstar;
    ITokenAdminRegistry tokenAdminRegistrySoneium;

    uint64 chainSelectorAstar;
    uint64 chainSelectorSoneium;

    uint256 soneium;
    uint256 astar;

    uint256 deployerPk = vm.envUint("PRIVATE_KEY");

    string SONEIUM_RPC_URL = vm.envString("SONEIUM_RPC_URL");
    string ASTAR_RPC_URL = vm.envString("ASTAR_RPC_URL");

    address deployer;
    address manager;
    address rmnProxySoneium;
    address rmnProxyAstar;
    address routerSoneium;
    address routerAstar;

    function setUp() public {
        soneium = vm.createFork(SONEIUM_RPC_URL);
        astar = vm.createFork(ASTAR_RPC_URL);
        deployer = vm.addr(deployerPk);
        manager = 0xf9B9068276163f47cd5599750496c48BeEba7B44;

        rmnProxySoneium = 0x3117f515D763652A32d3D6D447171ea7c9d57218;
        routerSoneium = 0x8C8B88d827Fe14Df2bc6392947d513C86afD6977;
        rmnProxyAstar = 0x7317D216F3DCDa40144a54eC9bA09829a423cb35;
        routerAstar = 0x8D5c5CB8ec58285B424C93436189fB865e437feF;

        registryModuleOwnerCustomAstar = IRegistryModuleOwnerCustom(0x9c54A7E067E5bdB8e1A44eA7a657053780d35d58);
        tokenAdminRegistryAstar = ITokenAdminRegistry(0xB98eEd70e3cE8E342B0f770589769E3A6bc20A09);
        chainSelectorAstar = 6422105447186081193;

        registryModuleOwnerCustomSoneium = IRegistryModuleOwnerCustom(0x1d0B6B3ef94dD6A68b7E16bd8B01fca9EA8e3d6E);
        tokenAdminRegistrySoneium = ITokenAdminRegistry(0x5ba21F6824400B91F232952CA6d7c8875C1755a4);
        chainSelectorSoneium = 12505351618335765396;
    } // prettier-ignore

    function run() public {
        // setup

        // address poolAstar = 0x893855bd21519CA7c321BEB1cdd493473dF0582e;
        // address poolSoneium = 0xc071B8E36B6bC20990951848Ee9997bAEFb07113;
        // address mythoAstar = 0xCFA795310bD2b2bf0E50fc50D3559B4aD591b74E;
        // address mythoSoneium = 0x197dB89FBbad7C0D23feA80539c20F2F05Ca694F;

        fork(soneium);

        TokenPool.ChainUpdate[]
            memory chainUpdatesSoneium = new TokenPool.ChainUpdate[](1);
        chainUpdatesSoneium[0] = TokenPool.ChainUpdate({
            remoteChainSelector: chainSelectorAstar, // astar's selector
            allowed: true,
            remotePoolAddress: abi.encode(address(poolAstar)),
            remoteTokenAddress: abi.encode(address(mythoAstar)),
            outboundRateLimiterConfig: RateLimiter.Config(false, 0, 0),
            inboundRateLimiterConfig: RateLimiter.Config(false, 0, 0)
        });

        registryModuleOwnerCustomSoneium.registerAdminViaOwner(address(mythoSoneium));
        tokenAdminRegistrySoneium.acceptAdminRole(address(mythoSoneium));
        tokenAdminRegistrySoneium.setPool(
            address(mythoSoneium),
            address(poolSoneium)
        );
        LockReleaseTokenPool(poolSoneium).applyChainUpdates(chainUpdatesSoneium);
        LockReleaseTokenPool(poolSoneium).setRemotePool(
            chainSelectorAstar,
            abi.encode(address(poolAstar))
        );

        // fork(astar);

        // TokenPool.ChainUpdate[]
        //     memory chainUpdatesSoneium = new TokenPool.ChainUpdate[](1);
        // chainUpdatesSoneium[0] = TokenPool.ChainUpdate({
        //     remoteChainSelector: chainSelectorSoneium,
        //     allowed: true,
        //     remotePoolAddress: abi.encode(address(poolSoneium)),
        //     remoteTokenAddress: abi.encode(address(mythoSoneium)),
        //     outboundRateLimiterConfig: RateLimiter.Config(false, 0, 0),
        //     inboundRateLimiterConfig: RateLimiter.Config(false, 0, 0)
        // });

        // registryModuleOwnerCustomAstar.registerAdminViaOwner(address(mythoAstar));
        // tokenAdminRegistryAstar.acceptAdminRole(address(mythoAstar));
        // tokenAdminRegistryAstar.setPool(
        //     address(mythoAstar),
        //     address(poolAstar)
        // );
        // BurnMintTokenPool(poolAstar).applyChainUpdates(chainUpdatesSoneium);
        // BurnMintTokenPool(poolAstar).setRemotePool(
        //     chainSelectorSoneium,
        //     abi.encode(address(poolSoneium))
        // );
    }

    function deployMythoAndPools() public {
        fork(soneium);

        MYTHO mythoSoneiumImpl = new MYTHO();
        proxySoneium = new TransparentUpgradeableProxy(
            address(mythoSoneiumImpl),
            deployer,
            ""
        );
        mythoSoneium = MYTHO(address(proxySoneium));
        mythoSoneium.initialize(deployer, deployer, deployer, deployer);

        poolSoneium = new LockReleaseTokenPool(
            IERC20(address(mythoSoneium)), // token
            new address[](0), // allowlist
            rmnProxySoneium, // rmnProxy
            false, // acceptLiquidity
            routerSoneium // router
        );

        console.log("Soneium pool deployed at: %s", address(poolSoneium));
        console.log("Soneium MYTHO deployed at: %s", address(mythoSoneium));

        fork(astar);

        MYTHO mythoAstarImpl = new MYTHO();
        proxyAstar = new TransparentUpgradeableProxy(
            address(mythoAstarImpl),
            deployer,
            ""
        );
        mythoAstar = MYTHO(address(proxyAstar));
        mythoAstar.initialize(deployer, deployer, deployer, deployer);

        poolAstar = new BurnMintTokenPool(
            IBurnMintERC20(address(mythoAstar)),
            new address[](0),
            rmnProxyAstar,
            routerAstar
        );

        console.log("Astar pool deployed at: %s", address(poolAstar));
        console.log("Astar MYTHO deployed at: %s", address(mythoAstar));
    }

    function fork(uint256 _forkId) internal {
        try vm.stopBroadcast() {} catch {}
        vm.selectFork(_forkId);
        vm.startBroadcast(deployerPk);
    }
}

//   Soneium pool deployed at: 0xc071B8E36B6bC20990951848Ee9997bAEFb07113
//   Soneium MYTHO deployed at: 0x197dB89FBbad7C0D23feA80539c20F2F05Ca694F
//   Astar pool deployed at: 0x893855bd21519CA7c321BEB1cdd493473dF0582e
//   Astar MYTHO deployed at: 0xCFA795310bD2b2bf0E50fc50D3559B4aD591b74E