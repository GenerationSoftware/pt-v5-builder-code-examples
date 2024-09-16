// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

struct QuoteParams {
    QuotePair quotePair;
    uint128 baseAmount;
    bytes data;
}

struct QuotePair {
    address base;
    address quote;
}

/// @title Oracle Interface
/// @author 0xSplits
interface IOracle {
    function getQuoteAmounts(QuoteParams[] calldata quoteParams_) external view returns (uint256[] memory);
}