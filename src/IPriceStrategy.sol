// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IPriceStrategy {

    // returns erc20 token value
    function price(uint256 tokenId) external view returns (uint256);

}
