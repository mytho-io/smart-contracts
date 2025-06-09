// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console, console2, StdStyle} from "forge-std/Script.sol";

import {OFT} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IMessageLibManager, SetConfigParam} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {IOFT, SendParam, OFTLimit, OFTReceipt, OFTFeeDetail, MessagingReceipt, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import {ExecutorConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol";

contract DoOftSending is Script {
    using OptionsBuilder for bytes;

    uint256 ethereum;
    uint256 soneium;

    uint256 deployerPk = vm.envUint("PRIVATE_KEY");

    OFT tokenEth;
    OFT tokenSoneium;

    ILayerZeroEndpointV2 endpointSoneium;
    ILayerZeroEndpointV2 endpointEthereum;

    address sendLibSon;
    address sendLibEth;
    address receiveLibSon;
    address receiveLibEth;
    address yaySon;
    address yayEth;
    address executorSon;
    address executorEth;
    address dvnSon;
    address dvnEth;

    string ETHEREUM_RPC_URL = vm.envString("ETHEREUM_RPC_URL");
    string SONEIUM_RPC_URL = vm.envString("SONEIUM_RPC_URL");

    address deployer;
    address user;

    uint32 ethId = 30101;
    uint32 sonId = 30340;

    function setUp() public {
        ethereum = vm.createFork(ETHEREUM_RPC_URL);
        soneium = vm.createFork(SONEIUM_RPC_URL);

        tokenEth = OFT(0xbC223E0054bFAaC419c038fB75eA22758EaC71af);
        tokenSoneium = OFT(0x4F802625E02907b2CF0409a35288617e5CB7C762);

        yaySon = 0x54e86315C03217b76A7466C302245fD10ebEf25A;
        yayEth = 0x4b18d95B3CA275AdaD67F1dC81c0FE0D1FB58d59;

        sendLibSon = 0x50351C9dA75CCC6d8Ea2464B26591Bb4bd616dD5;
        sendLibEth = 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1;

        receiveLibSon = 0x364B548d8e6DB7CA84AaAFA54595919eCcF961eA;
        receiveLibEth = 0xc02Ab410f0734EFa3F14628780e6e695156024C2;

        executorSon = 0xAE3C661292bb4D0AEEe0588b4404778DF1799EE6;
        executorEth = 0x173272739Bd7Aa6e4e214714048a9fE699453059;

        dvnSon = 0xfDfA2330713A8e2EaC6e4f15918F11937fFA4dBE;
        dvnEth = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b;

        endpointSoneium = ILayerZeroEndpointV2(
            0x4bCb6A963a9563C33569D7A512D35754221F3A19
        );
        endpointEthereum = ILayerZeroEndpointV2(
            0x1a44076050125825900e736c501f859c50fE728c
        );

        deployer = vm.addr(deployerPk);
        user = 0xf9B9068276163f47cd5599750496c48BeEba7B44;
    }

    function run() public {
        // Configure Ethereum (Chain B)
        fork(ethereum);

        console.log(tokenEth.balanceOf(deployer));

        // _getConfig(
        //     address(endpointEthereum),
        //     yayEth,
        //     sendLibEth,
        //     sonId,
        //     2
        // );

        // _setLibraries(
        //     address(endpointEthereum),
        //     address(tokenEth),
        //     sonId,
        //     sendLibEth,
        //     receiveLibEth
        // );
        // _setSendConfig(
        //     address(endpointEthereum),
        //     address(tokenEth),
        //     sonId,
        //     sendLibEth,
        //     dvnEth,
        //     executorEth,
        //     20
        // );
        // _setReceiveConfig(
        //     address(endpointEthereum),
        //     address(tokenEth),
        //     sonId,
        //     receiveLibEth,
        //     dvnEth,
        //     20
        // );

        _send(address(tokenEth), sonId, deployer, 1e18);

        // Configure Soneium (Chain A)
        fork(soneium);

        console.log(tokenSoneium.balanceOf(deployer));

        // _setLibraries(
        //     address(endpointSoneium),
        //     address(tokenSoneium),
        //     ethId,
        //     sendLibSon,
        //     receiveLibSon
        // );
        // _setSendConfig(
        //     address(endpointSoneium),
        //     address(tokenSoneium),
        //     sonId,
        //     sendLibSon,
        //     dvnSon,
        //     executorSon,
        //     20
        // );
        // _setReceiveConfig(
        //     address(endpointSoneium),
        //     address(tokenSoneium),
        //     sonId,
        //     receiveLibSon,
        //     dvnSon,
        //     20
        // );

        // Send from Soneium to Ethereum
        // _send();

        console.log(tokenSoneium.balanceOf(deployer));

        // _getConfig(
        //     address(endpointSoneium),
        //     0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590,
        //     sendLibSon,
        //     ethId,
        //     2
        // );
    }

    function _send(
        address _oapp,
        uint32 _destId,
        address _receiver,
        uint256 _amount
    ) internal {
        bytes memory options = OptionsBuilder
            .newOptions()
            .addExecutorLzReceiveOption(200000, 0);

        SendParam memory sendParam = SendParam({
            dstEid: _destId,
            to: bytes32(uint256(uint160(bytes20(_receiver)))),
            amountLD: _amount,
            minAmountLD: _amount,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = OFT(_oapp).quoteSend(sendParam, false);
        OFT(_oapp).send{value: fee.nativeFee}(sendParam, fee, deployer);
    }

    /// @notice Calls getConfig on the specified LayerZero Endpoint.
    /// @dev Decodes the returned bytes as a UlnConfig. Logs some of its fields.
    /// @param _endpoint The LayerZero Endpoint address.
    /// @param _oapp The address of your OApp.
    /// @param _lib The address of the Message Library (send or receive).
    /// @param _eid The remote endpoint identifier.
    /// @param _configType The configuration type (1 = Executor, 2 = ULN).
    function _getConfig(
        address _endpoint,
        address _oapp,
        address _lib,
        uint32 _eid,
        uint32 _configType
    ) internal view {
        // Instantiate the LayerZero endpoint.
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(_endpoint);
        // Retrieve the raw configuration bytes.
        bytes memory config = endpoint.getConfig(
            _oapp,
            _lib,
            _eid,
            _configType
        );

        if (_configType == 1) {
            // Decode the Executor config (configType = 1)
            ExecutorConfig memory execConfig = abi.decode(
                config,
                (ExecutorConfig)
            );
            // Log some key configuration parameters.
            console.log("Executor Type:", execConfig.maxMessageSize);
            console.log("Executor Address:", execConfig.executor);
        }

        if (_configType == 2) {
            // Decode the ULN config (configType = 2)
            UlnConfig memory decodedConfig = abi.decode(config, (UlnConfig));
            // Log some key configuration parameters.
            console.log("Confirmations:", decodedConfig.confirmations);
            console.log("Required DVN Count:", decodedConfig.requiredDVNCount);
            for (uint i = 0; i < decodedConfig.requiredDVNs.length; i++) {
                console.logAddress(decodedConfig.requiredDVNs[i]);
            }
            console.log("Optional DVN Count:", decodedConfig.optionalDVNCount);
            for (uint i = 0; i < decodedConfig.optionalDVNs.length; i++) {
                console.logAddress(decodedConfig.optionalDVNs[i]);
            }
            console.log(
                "Optional DVN Threshold:",
                decodedConfig.optionalDVNThreshold
            );
        }
    }

    function _setLibraries(
        address _endpoint,
        address _oapp,
        uint32 _eid,
        address _sendLib,
        address _receiveLib
    ) internal {
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(
            address(_endpoint)
        );

        endpoint.setSendLibrary(address(_oapp), _eid, _sendLib);
        endpoint.setReceiveLibrary(address(_oapp), _eid, _receiveLib, 0);
    }

    function _setSendConfig(
        address _endpoint,
        address _oapp,
        uint32 _eid,
        address _sendLib,
        address _dvn,
        address _executor,
        uint64 _confirmations
    ) internal {
        uint32 EXECUTOR_CONFIG_TYPE = 1;
        uint32 ULN_CONFIG_TYPE = 2;

        address endpoint = _endpoint;
        address oapp = _oapp;
        uint32 eid = _eid;
        address sendLib = _sendLib;

        address[] memory dvns = new address[](1);
        dvns[0] = _dvn;

        /// @notice ULNConfig defines security parameters (DVNs + confirmation threshold)
        /// @notice Send config requests these settings to be applied to the DVNs and Executor
        /// @dev 0 values will be interpretted as defaults, so to apply NIL settings, use:
        /// @dev uint8 internal constant NIL_DVN_COUNT = type(uint8).max;
        /// @dev uint64 internal constant NIL_CONFIRMATIONS = type(uint64).max;
        UlnConfig memory uln = UlnConfig({
            confirmations: _confirmations, // minimum block confirmations required
            requiredDVNCount: 1, // number of DVNs required
            optionalDVNCount: type(uint8).max, // optional DVNs count, uint8
            optionalDVNThreshold: 0, // optional DVN threshold
            requiredDVNs: dvns, // sorted list of required DVN addresses
            optionalDVNs: new address[](0) // sorted list of optional DVNs
        });

        /// @notice ExecutorConfig sets message size limit + fee‑paying executor
        ExecutorConfig memory exec = ExecutorConfig({
            maxMessageSize: 10000, // max bytes per cross-chain message
            executor: _executor // address that pays destination execution fees
        });

        bytes memory encodedUln = abi.encode(uln);
        bytes memory encodedExec = abi.encode(exec);

        SetConfigParam[] memory params = new SetConfigParam[](2);
        params[0] = SetConfigParam(eid, EXECUTOR_CONFIG_TYPE, encodedExec);
        params[1] = SetConfigParam(eid, ULN_CONFIG_TYPE, encodedUln);

        ILayerZeroEndpointV2(endpoint).setConfig(oapp, sendLib, params);
    }

    function _setReceiveConfig(
        address _endpoint,
        address _oapp,
        uint32 _eid,
        address _receiveLib,
        address _dvn,
        uint64 _confirmations
    ) internal {
        uint32 RECEIVE_CONFIG_TYPE = 2;

        address endpoint = _endpoint;
        address oapp = _oapp;
        uint32 eid = _eid;
        address receiveLib = _receiveLib;

        address[] memory dvns = new address[](1);
        dvns[0] = _dvn;

        /// @notice UlnConfig controls verification threshold for incoming messages
        /// @notice Receive config enforces these settings have been applied to the DVNs and Executor
        /// @dev 0 values will be interpretted as defaults, so to apply NIL settings, use:
        /// @dev uint8 internal constant NIL_DVN_COUNT = type(uint8).max;
        /// @dev uint64 internal constant NIL_CONFIRMATIONS = type(uint64).max;
        UlnConfig memory uln = UlnConfig({
            confirmations: _confirmations, // min block confirmations from source
            requiredDVNCount: 1, // required DVNs for message acceptance
            optionalDVNCount: type(uint8).max, // optional DVNs count
            optionalDVNThreshold: 0, // optional DVN threshold
            requiredDVNs: dvns, // sorted required DVNs
            optionalDVNs: new address[](0) // no optional DVNs
        });

        bytes memory encodedUln = abi.encode(uln);

        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam(eid, RECEIVE_CONFIG_TYPE, encodedUln);

        ILayerZeroEndpointV2(endpoint).setConfig(oapp, receiveLib, params);
    }

    function fork(uint256 _forkId) internal {
        try vm.stopBroadcast() {} catch {}
        vm.selectFork(_forkId);
        vm.startBroadcast(deployerPk);
    }

    function prank(address _addr) internal {
        vm.stopPrank();
        vm.startPrank(_addr);
    }
}

// struct SendParam {
//     uint32 dstEid; // Destination endpoint ID.
//     bytes32 to; // Recipient address.
//     uint256 amountLD; // Amount to send in local decimals.
//     uint256 minAmountLD; // Minimum amount to send in local decimals.
//     bytes extraOptions; // Additional options supplied by the caller to be used in the LayerZero message.
//     bytes composeMsg; // The composed message for the send() operation.
//     bytes oftCmd; // The OFT command to be executed, unused in default OFT implementations.
// }

// soneium 0x4F802625E02907b2CF0409a35288617e5CB7C762 / 0x4f802625e02907b2cf0409a35288617e5cb7c762000000000000000000000000
// ethereum 0xbC223E0054bFAaC419c038fB75eA22758EaC71af / 0xbc223e0054bfaac419c038fb75ea22758eac71af000000000000000000000000

// lz endpoint soneium 0x4bcb6a963a9563c33569d7a512d35754221f3a19 / eid 30340 / chainId 1868
// lz endpoint ethereum 0x1a44076050125825900e736c501f859c50fE728c / eid 30101 / chainId 1

// my addr 0x7ECD92b9835E0096880bF6bA778d9eA40d1338B5
// yaystone 0x54e86315C03217b76A7466C302245fD10ebEf25A
