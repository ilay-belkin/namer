// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/NamesRegistry.sol";
import "../src/IPriceStrategy.sol";
import "../src/FixedPriceStrategy.sol";
import "./FakeUSD.sol";

contract NamesRegistryTest is Test {
    NamesRegistry public registry;
    IERC20 public erc20;
    IPriceStrategy public priceStrategy;
    IPriceStrategy public userPriceStrategy;

    address constant DEPLOYER = address(100);
    address constant GENESIS_OWNER = address(200);
    address constant USER = address(300);
    address constant USER_2 = address(400);

    function setUp() public {
        vm.prank(DEPLOYER);
        erc20 = new FakeUSD();

        priceStrategy = new FixedPriceStrategy(uint256(10));
        userPriceStrategy = new FixedPriceStrategy(uint256(5));
        registry = new NamesRegistry(erc20);
        registry.initialize(
            GENESIS_OWNER,
            address(priceStrategy),
            LibTax.Fraction(1, 100) // 1%
        );
    }

    function testMintTopLevel_and_duplicate_check() public {
        vm.prank(DEPLOYER);
        erc20.transfer(USER, 21);

        vm.prank(USER);
        erc20.approve(address(registry), 10);

        string[] memory parts = new string[](1);
        parts[0] = "projectname";
        uint256 tokenId = requestAndMint(USER, parts);
        assert(registry.ownerOf(tokenId) == USER);
        assert(compareStrings(registry.name(tokenId), "projectname"));

        assert(erc20.balanceOf(USER) == 11);
        assert(erc20.balanceOf(GENESIS_OWNER) == 10);
        assert(erc20.balanceOf(address(registry)) == 0); // zero fees for now

        request(USER_2, parts);
        vm.prank(USER_2);
        vm.expectRevert("Already minted token");
        registry.mintNewName(parts, 12, 2);
    }

    function testMintManyLevels() public {
        vm.prank(DEPLOYER);
        erc20.transfer(USER, 21);
        vm.prank(DEPLOYER);
        erc20.transfer(USER_2, 5);

        vm.prank(USER);
        erc20.approve(address(registry), 10);

        string[] memory parts = new string[](1);
        parts[0] = "projectname";
        uint256 tokenId = requestAndMint(USER, parts);
        assert(registry.ownerOf(tokenId) == USER);
        assert(compareStrings(registry.name(tokenId), "projectname"));

        assert(erc20.balanceOf(USER) == 11);
        assert(erc20.balanceOf(GENESIS_OWNER) == 10);
        assert(erc20.balanceOf(address(registry)) == 0); // zero fees for now

        string[] memory parts2 = new string[](2);
        parts2[0] = "goodman";
        parts2[1] = "projectname";
        tokenId = requestAndMint(USER, parts2);
        assert(registry.ownerOf(tokenId) == USER);
        assert(compareStrings(registry.name(tokenId), "goodman.namer"));

        assert(erc20.balanceOf(USER) == 11); // free mint to parent owner
        assert(erc20.balanceOf(GENESIS_OWNER) == 10);
        assert(erc20.balanceOf(address(registry)) == 0); // zero fees for now

        vm.prank(USER);
        registry.setMintPriceStrategy(address(userPriceStrategy));

        vm.prank(USER_2);
        erc20.approve(address(registry), 5);

        string[] memory parts3 = new string[](3);
        parts3[0] = "saul";
        parts3[1] = "goodman";
        parts3[2] = "projectname";
        tokenId = requestAndMint(USER_2, parts3);
        assert(registry.ownerOf(tokenId) == USER_2);
        assert(compareStrings(registry.name(tokenId), "saul.goodman.namer"));

        assert(erc20.balanceOf(USER) == 16); // USER received custom price 5FUSD
        assert(erc20.balanceOf(USER_2) == 0); // USER_2 gave all "five bucks" for nft
        assert(erc20.balanceOf(GENESIS_OWNER) == 10); // GENESIS_OWNER receives nothing
        assert(erc20.balanceOf(address(registry)) == 0); // zero fees for now
    }

    function testMintSLD_to_non_existent_TLD() public {
        string[] memory parts = new string[](2);
        parts[0] = "goodman";
        parts[1] = "projectname";

        request(USER, parts);
        vm.prank(USER);
        vm.expectRevert("Non-existent token");
        registry.mintNewName(parts, 10, 1);
    }

    function request(address sender, string[] memory parts) internal {
        string memory uri = LibUri.uri(parts);
        uint256 request = uint256(keccak256(abi.encodePacked(sender, uri)));

        vm.prank(sender);
        registry.createPendingRegistryRequest(request);
    }

    function requestAndMint(address sender, string[] memory parts) internal returns (uint256) {
        string memory uri = LibUri.uri(parts);
        uint256 request = uint256(keccak256(abi.encodePacked(sender, uri)));

        vm.prank(sender);
        registry.createPendingRegistryRequest(request);

        vm.prank(sender);
        return registry.mintNewName(parts, 10, 1);
    }

    function compareStrings(string memory a, string memory b) public pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }
}
