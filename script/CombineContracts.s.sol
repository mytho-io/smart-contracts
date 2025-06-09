// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

contract CombineContracts is Script {
    function run() public {
        // List of contract files to combine
        string[] memory contractFiles = new string[](7);
        contractFiles[0] = "src/MeritManager.sol";
        contractFiles[1] = "src/TotemFactory.sol";
        contractFiles[2] = "src/TotemTokenDistributor.sol";
        contractFiles[3] = "src/TotemToken.sol";
        contractFiles[4] = "src/Totem.sol";
        contractFiles[5] = "src/MYTHO.sol";
        contractFiles[6] = "src/Treasury.sol";

        // Read file contents and combine them
        // string memory combinedContent = "// SPDX-License-Identifier: MIT\npragma solidity ^0.8.20;\n\n";
        string memory combinedContent;

        for (uint256 i = 0; i < contractFiles.length; i++) {
            string memory fileContent = vm.readFile(contractFiles[i]);
            combinedContent = string.concat(combinedContent, "\n// --- ", contractFiles[i], " ---\n");
            combinedContent = string.concat(combinedContent, fileContent);
        }

        // Write the combined content
        string memory outputPath = "combined/CombinedContracts.sol";
        vm.writeFile(outputPath, combinedContent);
    }
}
