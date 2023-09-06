// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

import "./LibTree.sol";
import "./LibTax.sol";
import "./LibTime.sol";
import "./LibUri.sol";
import "./IPriceStrategy.sol";

contract NamesRegistry is ERC721, Ownable, Initializable {

    // disable name buy out after mint; for owner convenience
    uint256 AFTER_TAX_PERIOD_START_FREEZE_DAYS = 3;

    // grace period for name owner to buy out outdated name
    uint256 AFTER_TAX_PERIOD_END_FREEZE_DAYS = 30;

    struct TaxRecord {
        uint256 taxBase; // base price for reselling and tax calculation
        uint256 periodStart; // seconds, based on block.timestamp
        uint256 periodEnd; // seconds, based on block.timestamp + rent period
    }

    // token used for all prices and payments
    IERC20 internal _erc20;

    event NewTaxRecord(uint256 tokenId, uint256 taxBase, uint256 periodStart, uint256 periodEnd);
    event NewURI(uint256 tokenId, string uri);

    // tokenId to full uri (move to metadata??)
    mapping(uint256 => string) internal _tokenNames;

    // address to keccak(address + uri)
    mapping(address => uint256) internal _pendingRequests;

    // price strategies for minting subdomains;
    // owner to IPriceStrategy contract
    mapping(address => address) internal _mintPriceStrategies;

    // tokenId to TaxRecord struct
    mapping(uint256 => TaxRecord) internal _tokenTaxRecords;

    // current tax rate
    LibTax.Fraction internal _taxRate;

    constructor(IERC20 erc20) ERC721("Names Registry", "NMS") {
        _erc20 = erc20;
    }

    function initialize(
        address genesisOwner,
        address priceStrategy,
        LibTax.Fraction memory taxRate
    ) initializer public {
        _taxRate = taxRate;
        _mint(genesisOwner, LibTree.GENESIS_TOKEN_ID);
        _mintPriceStrategies[genesisOwner] = priceStrategy;
    }

    function setMintPriceStrategy(address strategy) public {
        IPriceStrategy(strategy).price(LibTree.GENESIS_TOKEN_ID);
        // todo how to check ability
        _mintPriceStrategies[_msgSender()] = strategy;
    }

    // request = keccak256(address + uri)
    // uri samples: "projectname" (TLD), "username.projectname" (SLD), etc.
    function createPendingRegistryRequest(uint256 request) public {
        _pendingRequests[_msgSender()] = request;
    }

    // mint new name token under some parent name;
    // parts e.g. ["projectname"] - TLD
    // parts e.g. ["username", "projectname"] - SLD
    // taxBase - price for tax calculation and buy out
    // yearsCount - duration of tax record / registration
    function mintNewName(string[] memory parts, uint256 taxBase, uint256 yearsCount) public returns (uint256) {
        uint256 pendingRequest = uint256(keccak256(abi.encodePacked(_msgSender(), LibUri.uri(parts))));
        require(
            _pendingRequests[_msgSender()] == pendingRequest,
            "Invalid pending request"
        );
        delete _pendingRequests[_msgSender()];

        (uint256 parentId, uint256  tokenId) = LibTree.namehash(parts);
        require(_exists(parentId), "Non-existent token");
        require(!_exists(tokenId), "Already minted token");

        address parentNameOwner = _ownerOf(parentId);

        uint256 mintPrice;
        if (_msgSender() == parentNameOwner) {
            mintPrice = 0;
            // free mint for parent name owner
        } else {
            mintPrice = IPriceStrategy(_mintPriceStrategies[parentNameOwner]).price(tokenId);
        }
        uint256 taxValue = LibTax.tax(taxBase, yearsCount, _taxRate);
        uint256 fullPrice = mintPrice + taxValue;
        require(_erc20.allowance(_msgSender(), address(this)) >= fullPrice, "Check token allowance");
        SafeERC20.safeTransferFrom(
            _erc20,
            _msgSender(),
            parentNameOwner,
            mintPrice
        );
        SafeERC20.safeTransferFrom(
            _erc20,
            _msgSender(),
            address(this),
            taxValue
        );
        _mint(_msgSender(), tokenId);
        _tokenNames[tokenId] = LibUri.uri(parts);
        _tokenTaxRecords[tokenId] = TaxRecord(
            taxBase,
            block.timestamp,
            block.timestamp + LibTime.yearsToSeconds(yearsCount)
        );
        emit NewTaxRecord(
            tokenId,
            _tokenTaxRecords[tokenId].taxBase,
            _tokenTaxRecords[tokenId].periodStart,
            _tokenTaxRecords[tokenId].periodEnd
        );
        emit NewURI(
            tokenId, _tokenNames[tokenId]
        );
        return tokenId;
    }

    // e.g. "username.projectname", "projectname"
    function name(uint256 tokenId) public view returns (string memory) {
        require(_exists(tokenId), "Non-existent token");
        return _tokenNames[tokenId];
    }

    // universal buy method:
    // buy name with valid tax record
    // or name with outdated tax record
    // or owner can
    function buy(uint256 tokenId, uint256 newTaxBase, uint256 additionalYearsCount) public {
        TaxRecord memory taxRecord = _tokenTaxRecords[tokenId];
        require(
            taxRecord.periodStart + LibTime.daysToSeconds(AFTER_TAX_PERIOD_START_FREEZE_DAYS) < block.timestamp,
            "Freeze after tax period start"
        );
        if (taxRecord.periodEnd >= block.timestamp) {// valid tax record
            uint256 periodEnd;
            if (additionalYearsCount > 0) {
                periodEnd = taxRecord.periodEnd + LibTime.yearsToSeconds(additionalYearsCount);
            } else {
                periodEnd = taxRecord.periodEnd;
            }
            uint256 newPeriodTax = LibTax.tax(newTaxBase, additionalYearsCount, _taxRate);
            // tax for additional years
            uint256 currentPeriodTaxRecalc = 0;
            if (newTaxBase > taxRecord.taxBase) {
                uint256 daysLeft = LibTime.secondsToDays(taxRecord.periodEnd - block.timestamp);
                currentPeriodTaxRecalc = (LibTax.tax(newTaxBase - taxRecord.taxBase, 1, _taxRate) / 365) * daysLeft;
            }
            uint256 fullPrice = taxRecord.taxBase + newPeriodTax + currentPeriodTaxRecalc;
            require(_erc20.allowance(_msgSender(), address(this)) >= fullPrice, "Check token allowance");

            SafeERC20.safeTransferFrom(
                _erc20,
                _msgSender(),
                _ownerOf(tokenId),
                taxRecord.taxBase
            );
            SafeERC20.safeTransferFrom(
                _erc20,
                _msgSender(),
                address(this),
                newPeriodTax + currentPeriodTaxRecalc
            );
            safeTransferFrom(
                ownerOf(tokenId),
                _msgSender(),
                tokenId
            );
            _tokenTaxRecords[tokenId] = TaxRecord(newTaxBase, taxRecord.periodStart, periodEnd);

            emit NewTaxRecord(
                tokenId,
                _tokenTaxRecords[tokenId].taxBase,
                _tokenTaxRecords[tokenId].periodStart,
                _tokenTaxRecords[tokenId].periodEnd
            );
        } else {// outdated tax record
            require(
                _msgSender() == _ownerOf(tokenId)
                || block.timestamp > taxRecord.periodEnd + LibTime.daysToSeconds(AFTER_TAX_PERIOD_END_FREEZE_DAYS),
                "Freeze after tax period end"
            );
            uint256 newPeriodTax = LibTax.tax(newTaxBase, additionalYearsCount, _taxRate);
            uint256 mintPrice = IPriceStrategy(_mintPriceStrategies[_ownerOf(tokenId)]).price(tokenId);
            uint256 fullPrice = mintPrice + newPeriodTax;
            require(_erc20.allowance(_msgSender(), address(this)) >= fullPrice, "Check token allowance");

            SafeERC20.safeTransferFrom(
                _erc20,
                _msgSender(),
                _ownerOf(tokenId),
                mintPrice // mint price goes to previous owner
            );
            SafeERC20.safeTransferFrom(
                _erc20,
                _msgSender(),
                address(this),
                newPeriodTax // tax goes to contract
            );
            safeTransferFrom(
                ownerOf(tokenId),
                _msgSender(),
                tokenId
            );
            _tokenTaxRecords[tokenId] = TaxRecord(
                newTaxBase,
                block.timestamp,
                block.timestamp + LibTime.yearsToSeconds(additionalYearsCount)
            );
            emit NewTaxRecord(
                tokenId,
                _tokenTaxRecords[tokenId].taxBase,
                _tokenTaxRecords[tokenId].periodStart,
                _tokenTaxRecords[tokenId].periodEnd
            );
        }
    }

    function _onlyOwner(uint256 tokenId) internal view {
        require(ownerOf(tokenId) == _msgSender(), 'Registry: SENDER_IS_NOT_OWNER');
    }
}
