// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {MeritManager as MM} from "../src/MeritManager.sol";
import {TotemFactory as TF} from "../src/TotemFactory.sol";
import {TotemTokenDistributor as TTD} from "../src/TotemTokenDistributor.sol";
import {TotemToken as TT} from "../src/TotemToken.sol";
import {Totem} from "../src/Totem.sol";
import {MYTHO} from "../src/MYTHO.sol";
import {Treasury} from "../src/Treasury.sol";
import {AddressRegistry} from "../src/AddressRegistry.sol";
import {Layers as L} from "../src/Layers.sol";
import {Shards} from "../src/Shards.sol";
import {BoostSystem} from "../src/BoostSystem.sol";

import {MockToken} from "./mocks/MockToken.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {TokenHoldersOracle} from "../src/utils/TokenHoldersOracle.sol";

import {IUniswapV2Factory} from "@uniswap-v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@uniswap-v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {WETH} from "lib/solmate/src/tokens/WETH.sol";

import {Deployer} from "test/util/Deployer.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract DoTest is Test {
    L layers;
    BoostSystem bs;
    MM mm;

    address deployer;
    uint256 frontendSignerPk;

    function setUp() public {
        layers = L(0xB1d122d1329dbF9a125cDf978a0b6190C93f7FFB);
        bs = BoostSystem(0x7278eE249dD284FA04732Bc6dB339BAEca3F44ad);
        mm = MM(0x622A3667AA0A879EEB63011c63B6395feBe38880);

        // Получаем приватный ключ из переменной окружения
        frontendSignerPk = vm.envUint("FRONTEND_SIGNER_PK");
    }

    function test_do() public {
        // address user = 0x7ECD92b9835E0096880bF6bA778d9eA40d1338B5;
        // address totemAddr = address(0xda54c191ea8e5e2C1A774eb6f607b90d77FCeC87);

        // prank(user);

        // uint256 timestamp = block.timestamp;
        // bytes memory signature = createBoostSignature(
        //     user,
        //     totemAddr,
        //     timestamp
        // );

        // uint256 currentPeriod = mm.currentPeriod();
        // uint256 meritPointsBefore = mm.getTotemMeritPoints(totemAddr, currentPeriod);
        // console.log(meritPointsBefore);
        // bs.boost(totemAddr, timestamp, signature);
        // console.log(mm.getTotemMeritPoints(totemAddr, currentPeriod));
    }

    /**
     * @notice Создает подпись для функции boost()
     * @param user Адрес пользователя
     * @param totemAddr Адрес тотема
     * @param timestamp Временная метка
     * @return signature Подпись для передачи в boost()
     */
    function createBoostSignature(
        address user,
        address totemAddr,
        uint256 timestamp
    ) internal view returns (bytes memory) {
        // Создаем хеш сообщения как в контракте
        bytes32 messageHash = keccak256(
            abi.encodePacked(user, totemAddr, timestamp)
        );

        // Создаем Ethereum Signed Message Hash
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            messageHash
        );

        // Подписываем приватным ключом frontend signer'а
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            frontendSignerPk,
            ethSignedMessageHash
        );

        // Возвращаем подпись в формате bytes
        return abi.encodePacked(r, s, v);
    }

    // Utility function to prank as a specific user
    function prank(address _user) internal {
        vm.stopPrank();
        vm.startPrank(_user);
    }

    function warp(uint256 _time) internal {
        vm.warp(block.timestamp + _time);
    }
}
