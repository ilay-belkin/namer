// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;


library LibTax {

    struct Fraction {
        uint256 numerator;
        uint256 denominator;
    }

    function tax(uint256 value, uint256 periods, Fraction memory taxRate) external pure returns (uint256) {
        return (value / taxRate.denominator) * taxRate.numerator * periods;
    }

}
