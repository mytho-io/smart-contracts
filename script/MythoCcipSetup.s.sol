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
import {BurnMintMYTHO} from "../src/BurnMintMYTHO.sol";
import {AddressRegistry} from "../src/AddressRegistry.sol";

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
    uint64 chainSelectorAstar;
    uint64 chainSelectorSoneium;
    uint64 chainSelectorArbitrum;

    uint256 soneium;
    uint256 astar;
    uint256 arbitrum;

    uint256 deployerPk = vm.envUint("PRIVATE_KEY");

    string SONEIUM_RPC_URL = vm.envString("SONEIUM_RPC_URL");
    string ASTAR_RPC_URL = vm.envString("ASTAR_RPC_URL");
    string ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");

    address deployer;
    address manager;

    function setUp() public {
        soneium = vm.createFork(SONEIUM_RPC_URL);
        astar = vm.createFork(ASTAR_RPC_URL);
        arbitrum = vm.createFork(ARBITRUM_RPC_URL);

        deployer = vm.addr(deployerPk);
        manager = 0xf9B9068276163f47cd5599750496c48BeEba7B44;

        chainSelectorAstar = 6422105447186081193;
        chainSelectorSoneium = 12505351618335765396;
        chainSelectorArbitrum = 4949039107694359620;
    } // prettier-ignore

    function run() public {
        // do

        // _deployMythoAndPools(
        //     0x3117f515D763652A32d3D6D447171ea7c9d57218, // _sourceRmnProxy
        //     0x8C8B88d827Fe14Df2bc6392947d513C86afD6977, // _sourceRouter
        //     0xC311a21e6fEf769344EB1515588B9d535662a145, // _remoteRmnProxy
        //     0x141fa059441E0ca23ce184B6A78bafD2A517DdE8 //  _remoteRouter
        // );

        address soneiumPool = 0xe2629839031bea8Dd370d109969c5033DcdEb9aA;
        address soneiumMytho = 0x131c5D0cF8F31ab4B202308e4102a667dDA2Fa64;
        address arbitrumPool = 0xC69391950883106321c6BA1EcEC205986245964A;
        address arbitrumMytho = 0xA0A6dBf6A68cDB8A479efBa2f68166914b82c79A;

        // fork(soneium);
        // console.log(IERC20(soneiumMytho).balanceOf(deployer));
        // console.log(IERC20(soneiumMytho).totalSupply());

        // fork(arbitrum);
        // console.log(IERC20(arbitrumMytho).balanceOf(deployer));
        // console.log(IERC20(arbitrumMytho).totalSupply());

        // console.log(BurnMintMYTHO(arbitrumMytho).isMinter(arbitrumPool));
        // console.log(BurnMintMYTHO(arbitrumMytho).isBurner(arbitrumPool));

        // _grantMintBurnAccess(
        //     arbitrumMytho,
        //     arbitrumPool
        // );

        fork(soneium);

        _ccipSetUp(
            chainSelectorArbitrum, // _remoteChainSelector
            soneiumPool, // _localPool
            arbitrumPool, // _remotePool
            soneiumMytho, // _localToken
            arbitrumMytho, // _remoteToken
            0x2c3D51c7B454cB045C8cEc92d2F9E717C7519106, // _registryModuleOwnerCustom
            0x5ba21F6824400B91F232952CA6d7c8875C1755a4  // _tokenAdminRegistry
        );

        fork(arbitrum);

        _ccipSetUp(
            chainSelectorSoneium, // _remoteChainSelector
            arbitrumPool, // _localPool
            soneiumPool, // _remotePool
            arbitrumMytho, // _localToken
            soneiumMytho, // _remoteToken
            0x1f1df9f7fc939E71819F766978d8F900B816761b, // _registryModuleOwnerCustom
            0x39AE1032cF4B334a1Ed41cdD0833bdD7c7E7751E  // _tokenAdminRegistry
        );
    }

    function _deployMythoAndPools(
        address _sourceRmnProxy,
        address _sourceRouter,
        address _remoteRmnProxy,
        address _remoteRouter
    ) internal {
        fork(soneium);

        AddressRegistry registryImpl = new AddressRegistry();
        TransparentUpgradeableProxy registryProxy = new TransparentUpgradeableProxy(
            address(registryImpl),
            deployer,
            ""
        );
        AddressRegistry registry = AddressRegistry(address(registryProxy));
        registry.initialize();

        MYTHO sourceMythoImpl = new MYTHO();
        TransparentUpgradeableProxy sourceProxy = new TransparentUpgradeableProxy(
            address(sourceMythoImpl),
            deployer,
            ""
        );
        MYTHO sourceToken = MYTHO(address(sourceProxy));
        sourceToken.initialize(deployer, address(registry));

        LockReleaseTokenPool sourcePool = new LockReleaseTokenPool(
            IERC20(address(sourceToken)), // token
            new address[](0), // allowlist
            _sourceRmnProxy, // rmnProxy
            false, // acceptLiquidity
            _sourceRouter // router
        );

        console.log("Source pool deployed at: %s", address(sourcePool));
        console.log("Source MYTHO deployed at: %s", address(sourceToken));

        fork(arbitrum);

        BurnMintMYTHO remoteMythoImpl = new BurnMintMYTHO();
        TransparentUpgradeableProxy remoteProxy = new TransparentUpgradeableProxy(
            address(remoteMythoImpl),
            deployer,
            ""
        );
        BurnMintMYTHO remoteToken = BurnMintMYTHO(address(remoteProxy));
        remoteToken.initialize();

        BurnMintTokenPool remotePool = new BurnMintTokenPool(
            IBurnMintERC20(address(remoteToken)),
            new address[](0),
            _remoteRmnProxy,
            _remoteRouter
        );

        console.log("Remote pool deployed at: %s", address(remotePool));
        console.log("Remote MYTHO deployed at: %s", address(remoteToken));
    }

    function _grantMintBurnAccess(
        address _localToken,
        address _localPool
    ) internal {
        BurnMintMYTHO(_localToken).grantMintAccess(_localPool);
        BurnMintMYTHO(_localToken).grantBurnAccess(_localPool);
    }

    function _ccipSetUp(
        uint64 _remoteChainSelector,
        address _localPool,
        address _remotePool,
        address _localToken,
        address _remoteToken,
        address _registryModuleOwnerCustom,
        address _tokenAdminRegistry
    ) internal {
        TokenPool.ChainUpdate[]
            memory chainUpdates = new TokenPool.ChainUpdate[](1);
        chainUpdates[0] = TokenPool.ChainUpdate({
            remoteChainSelector: _remoteChainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(_remotePool),
            remoteTokenAddress: abi.encode(_remoteToken),
            outboundRateLimiterConfig: RateLimiter.Config(false, 0, 0),
            inboundRateLimiterConfig: RateLimiter.Config(false, 0, 0)
        });

        IRegistryModuleOwnerCustom(_registryModuleOwnerCustom)
            .registerAdminViaOwner(_localToken);
        ITokenAdminRegistry(_tokenAdminRegistry).acceptAdminRole(
            _localToken
        );
        ITokenAdminRegistry(_tokenAdminRegistry).setPool(
            _localToken,
            _localPool
        );
        BurnMintTokenPool(_localPool).applyChainUpdates(chainUpdates);
        BurnMintTokenPool(_localPool).setRemotePool(
            _remoteChainSelector,
            abi.encode(_remotePool)
        );
    }

    function fork(uint256 _forkId) internal {
        try vm.stopBroadcast() {} catch {}
        vm.selectFork(_forkId);
        vm.startBroadcast(deployerPk);
    }
}

// == Logs ==
//   Soneium pool deployed at: 0xe2629839031bea8Dd370d109969c5033DcdEb9aA
//   Soneium MYTHO deployed at: 0x131c5D0cF8F31ab4B202308e4102a667dDA2Fa64
//   Arbitrum pool deployed at: 0xC69391950883106321c6BA1EcEC205986245964A
//   Arbitrum MYTHO deployed at: 0xA0A6dBf6A68cDB8A479efBa2f68166914b82c79A
