// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {IVRFCoordinatorV2Plus} from "@ccip/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {VRFV2PlusClient} from "@ccip/vrf/dev/libraries/VRFV2PlusClient.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @dev Minato deployment
 */
contract MinatoVRFTesting is Script {
    address vrfCoordinator;
    uint256 vrfSubscriptionId;
    bytes32 vrfKeyHash;

    uint256 minato;

    uint256 deployerPk = vm.envUint("PRIVATE_KEY");

    string MINATO_RPC_URL = vm.envString("MINATO_RPC_URL");

    address deployer;

    function setUp() public {
        minato = vm.createFork(MINATO_RPC_URL);
        deployer = vm.addr(deployerPk);

        // minato vrf config
        vrfCoordinator = 0x3Fa01AB73beB4EA09e78FC0849FCe31d0b035b47;
        vrfSubscriptionId = 110586606629607351084397527862915980192448378269538304305737515090960183799576;
        vrfKeyHash = 0x0c970a50393bea0011d5cec18c15c80c6deb37888b9ff579f476b3e52f6d3922;
    }

    function run() public {
        fork(minato);

        // Deploy VRF test contract
        VRFTest vrfTest = new VRFTest(
            vrfCoordinator,
            vrfSubscriptionId,
            vrfKeyHash
        );

        console.log("VRF Test contract deployed at:", address(vrfTest));

        // // Test VRF request
        // vrfTest.request();
        // console.log("VRF request sent, requestId:", vrfTest.requestId());

        vm.stopBroadcast();
    }

    function fork(uint256 _forkId) internal {
        vm.selectFork(_forkId);
        vm.startBroadcast(deployerPk);
    }
}

contract VRFTest is Ownable {
    // VRF Configuration
    IVRFCoordinatorV2Plus private vrfCoordinator;
    uint256 private vrfSubscriptionId;
    bytes32 private vrfKeyHash;
    uint32 private vrfCallbackGasLimit;
    uint16 private vrfRequestConfirmations;
    uint32 private vrfNumWords;

    uint256 public requestId;

    mapping(uint256 requestId => uint256 number) public response;

    event RandomWordsRequested(uint256 indexed requestId);
    event RandomWordsFulfilled(uint256 indexed requestId, uint256 randomWord);

    error OnlyCoordinatorCanFulfill(address have, address want);

    constructor(
        address _vrfCoordinator,
        uint256 _vrfSubscriptionId,
        bytes32 _vrfKeyHash
    ) Ownable(msg.sender) {
        vrfCoordinator = IVRFCoordinatorV2Plus(_vrfCoordinator);
        vrfSubscriptionId = _vrfSubscriptionId;
        vrfKeyHash = _vrfKeyHash;
        vrfCallbackGasLimit = 100000;
        vrfRequestConfirmations = 3;
        vrfNumWords = 1;
    }

    function request() external onlyOwner {
        // Request VRF for base reward amount using V2Plus format
        VRFV2PlusClient.RandomWordsRequest memory req = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: vrfKeyHash,
                subId: vrfSubscriptionId,
                requestConfirmations: vrfRequestConfirmations,
                callbackGasLimit: vrfCallbackGasLimit,
                numWords: vrfNumWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });

        requestId = vrfCoordinator.requestRandomWords(req);
        emit RandomWordsRequested(requestId);
    }

    function rawFulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) external {
        if (msg.sender != address(vrfCoordinator)) {
            revert OnlyCoordinatorCanFulfill(
                msg.sender,
                address(vrfCoordinator)
            );
        }
        fulfillRandomWords(_requestId, _randomWords);
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal {
        uint256 num = _randomWords[0];
        response[_requestId] = _calculateBaseReward(num);
        
        emit RandomWordsFulfilled(_requestId, num);
    }

    // Helper functions for testing
    function getResponse(uint256 _requestId) external view returns (uint256) {
        return response[_requestId];
    }

    function getLatestResponse() external view returns (uint256) {
        return response[requestId];
    }

    function updateVRFConfig(
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        uint32 _numWords
    ) external {
        vrfCallbackGasLimit = _callbackGasLimit;
        vrfRequestConfirmations = _requestConfirmations;
        vrfNumWords = _numWords;
    }

    function _calculateBaseReward(
        uint256 _randomWord
    ) private pure returns (uint256) {
        uint256 roll = _randomWord % 100; // 0-99

        // Premium boost probabilities:
        // 50% chance: 500 points
        // 25% chance: 700 points
        // 15% chance: 1000 points
        // 7% chance: 2000 points
        // 3% chance: 3000 points

        if (roll < 50) return 500; // 0-49: 50% chance
        if (roll < 75) return 700; // 50-74: 25% chance
        if (roll < 90) return 1000; // 75-89: 15% chance
        if (roll < 97) return 2000; // 90-96: 7% chance
        return 3000; // 97-99: 3% chance
    }
}
