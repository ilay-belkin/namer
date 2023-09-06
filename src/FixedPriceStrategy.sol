// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IPriceStrategy.sol";

contract FixedPriceStrategy is IPriceStrategy {

    uint256 _fixedPrice;

    constructor(uint256 fixedPrice) {
        _fixedPrice = fixedPrice;
    }

    function price(uint256 tokenId) external view returns (uint256) {
        return _fixedPrice;
    }

}
