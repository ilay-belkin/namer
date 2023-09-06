// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;


library LibTime {

    function yearsToSeconds(uint256 yearsCount) external pure returns (uint256) {
        return yearsCount * 365 * 24 * 60 * 60;
    }

    function daysToSeconds(uint256 daysCount) external pure returns (uint256) {
        return daysCount * 24 * 60 * 60;
    }

    function secondsToDays(uint secondsCount) external pure returns (uint256) {
        return secondsCount / (60 * 60 * 24);
    }
}
