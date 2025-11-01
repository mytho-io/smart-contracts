// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import { Posts } from "../src/Posts.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// interface ICoordinator {
//     function owner() external view returns (address);
//     function cancelSubscription(uint256 subId, address to) external;
// }

// contract DoTest is Test {
//     MinatoVRFRandomNumberBNB vrfRandomNumber;
//     ICoordinator coordinator;
//     Posts posts;

//     address deployer;

//     uint256 bnb;

//     string BNB_RPC_URL = vm.envString("BNB_RPC_URL");
//     uint256 deployerPk = vm.envUint("PRIVATE_KEY");
    
//     function setUp() public {
//         // deployer = vm.addr(deployerPk);
//         // bnb = vm.createFork(BNB_RPC_URL);
//         vrfRandomNumber = MinatoVRFRandomNumberBNB(0x1989A2cc97120cdEB08288405849A8e3EB288139);
//         coordinator = ICoordinator(0xd691f04bc0C9a24Edb78af9E005Cf85768F694C9);
//         posts = Posts(0xB1d122d1329dbF9a125cDf978a0b6190C93f7FFB);
//     }

//     function test() public {
//         address user = 0x29367D8F3E349E97aD2221242208dF92CF4E2186;
//         // uint256 subId = 72078557927052746969133710630195904013035552869385437689005722190078163626928;

//         prank(user);

//         // coordinator.cancelSubscription(subId, user);
//         IERC20(0x5A501b94F73f7a6fEe391e9E907Be326D544f643).approve(address(posts), 60024988900000000000000000);
//         posts.boostPost(
//             213, // postId
//             60024988900000000000000000 // amount
//         );
//     }

//     function prank(address _user) internal {
//         vm.stopPrank();
//         vm.startPrank(_user);
//     }
// }

// import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
// import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

// contract MinatoVRFRandomNumberBNB is VRFConsumerBaseV2Plus { // 
//     // Chainlink VRF variables
//     uint256 public s_subscriptionId; // 72078557927052746969133710630195904013035552869385437689005722190078163626928
//     address public constant VRF_COORDINATOR = 0xd691f04bc0C9a24Edb78af9E005Cf85768F694C9;
//     address public constant LINK_TOKEN = 0x404460C6A5EdE2D891e8297795264fDe62ADBB75;
//     bytes32 public constant KEY_HASH = 0x130dba50ad435d4ecc214aad0d5820474137bd68e7e77724144f27c3c377d3d4;
//     uint32 public constant CALLBACK_GAS_LIMIT = 100000;
//     uint16 public constant REQUEST_CONFIRMATIONS = 3;
//     uint32 public constant NUM_WORDS = 1;

//     // Storage for random number and request tracking
//     uint256 public latestRandomNumber;
//     mapping(uint256 => address) private s_requestIdToSender;

//     // Event to emit when a random number is received
//     event RandomNumberReceived(uint256 requestId, uint256 randomNumber);

//     /**
//      * @notice Constructor initializes the contract with VRF Coordinator and subscription ID
//      * @param subscriptionId The Chainlink VRF subscription ID
//      */
//     constructor(uint256 subscriptionId) VRFConsumerBaseV2Plus(VRF_COORDINATOR) {
//         s_subscriptionId = subscriptionId;
//     }

//     /**
//      * @notice Requests a random number from Chainlink VRF
//      * @dev Caller must ensure the subscription has sufficient LINK
//      */
//     function requestRandomNumber() external {
//         // Build the VRF request
//         bytes memory extraArgs = VRFV2PlusClient._argsToBytes(
//             VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
//         );

//         uint256 requestId = s_vrfCoordinator.requestRandomWords(
//             VRFV2PlusClient.RandomWordsRequest({
//                 keyHash: KEY_HASH,
//                 subId: s_subscriptionId,
//                 requestConfirmations: REQUEST_CONFIRMATIONS,
//                 callbackGasLimit: CALLBACK_GAS_LIMIT,
//                 numWords: NUM_WORDS,
//                 extraArgs: extraArgs
//             })
//         );

//         // Store the request ID and sender
//         s_requestIdToSender[requestId] = msg.sender;
//     }

//     /**
//      * @notice Callback function used by VRF Coordinator to return random numbers
//      * @param requestId The ID of the request
//      * @param randomWords Array of random numbers
//      */
//     function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
//         // Store the first random number (since NUM_WORDS = 1)
//         latestRandomNumber = randomWords[0];

//         // Emit event with the random number
//         emit RandomNumberReceived(requestId, latestRandomNumber);
//     }

//     /**
//      * @notice Get the latest random number
//      * @return The most recent random number received
//      */
//     function getLatestRandomNumber() external view returns (uint256) {
//         return latestRandomNumber;
//     }
// }