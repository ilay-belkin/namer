// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library LibUri {

    function uri(string[] memory parts) external pure returns (string memory) {
        bytes memory uri = bytes(parts[0]);
        for (uint256 i = 1; i < parts.length; i++) {
            uri = abi.encodePacked(uri, '.', parts[i]);
        }
        return string(uri);
    }

}
