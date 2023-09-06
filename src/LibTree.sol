// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library LibTree {

    uint256 constant GENESIS_TOKEN_ID = uint256(keccak256("namer_genesis"));

    function namehash(string[] memory labels) internal pure returns (uint256, uint256) {
        uint256 parentId;
        uint256 tokenId = GENESIS_TOKEN_ID;
        for (uint256 i = labels.length; i > 0; i--) {
            parentId = tokenId;
            tokenId = namehash(parentId, labels[i - 1]);
        }
        return (parentId, tokenId);
    }

    function namehash(uint256 parentTokenId, string memory namePart) internal pure returns (uint256) {
        require(bytes(namePart).length != 0, 'Registry: TOKEN_NAME_EMPTY');
        return uint256(keccak256(abi.encodePacked(parentTokenId, keccak256(abi.encodePacked(namePart)))));
    }

    function root() public pure returns (uint256) {
        return GENESIS_TOKEN_ID;
    }

}
