// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Vm } from "forge-std/Test.sol";
import { IUniswapV2Factory } from "@uniswap-v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import { IUniswapV2ERC20 } from "@uniswap-v2-core/contracts/interfaces/IUniswapV2ERC20.sol";
import { WETH } from "@solmate/tokens/WETH.sol";
import { IUniswapV2Router02 } from "@uniswap-v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

library Deployer {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function deployFactory(address _feeToSetter) internal returns (IUniswapV2Factory factory) {
        bytes memory args = abi.encode(_feeToSetter);
        bytes memory bytecode = abi.encodePacked(vm.getCode("UniswapV2Factory.sol:UniswapV2Factory"), args);
        assembly {
            factory := create(0, add(bytecode, 32), mload(bytecode))
        }
    }

    function deployERC20(uint256 mintAmount) internal returns (IUniswapV2ERC20 erc20) {
        bytes memory args = abi.encode(mintAmount);
        bytes memory bytecode = abi.encodePacked(vm.getCode("ERC20.sol:ERC20"), args);
        assembly {
            erc20 := create(0, add(bytecode, 32), mload(bytecode))
        }
    }

    function deployWETH() internal returns (WETH weth) {
        bytes memory bytecode = abi.encodePacked(vm.getCode("WETH9.sol:WETH9"), "");
        assembly {
            weth := create(0, add(bytecode, 32), mload(bytecode))
        }
    }

    function deployRouterV2(address _factory, address _weth) internal returns (IUniswapV2Router02 router) {
        bytes memory args = abi.encode(_factory, _weth);
        bytes memory bytecode = abi.encodePacked(vm.getCode("UniswapV2Router02.sol:UniswapV2Router02"), args);
        assembly {
            router := create(0, add(bytecode, 32), mload(bytecode))
        }
    }
}