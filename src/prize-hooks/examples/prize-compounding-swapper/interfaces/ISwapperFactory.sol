// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { IOracle, QuotePair } from "./IOracle.sol";
import { ISwapper } from "./ISwapper.sol";

struct OracleParams {
    IOracle oracle;
    CreateOracleParams createOracleParams;
}

struct CreateOracleParams {
    address factory;
    bytes data;
}

struct SetPairScaledOfferFactorParams {
    QuotePair quotePair;
    uint32 scaledOfferFactor;
}

struct CreateSwapperParams {
    address owner;
    bool paused;
    address beneficiary;
    address tokenToBeneficiary;
    OracleParams oracleParams;
    uint32 defaultScaledOfferFactor;
    SetPairScaledOfferFactorParams[] pairScaledOfferFactors;
}

/// @title Swapper Factory Interface
/// @author 0xSplits
interface ISwapperFactory {
    function createSwapper(CreateSwapperParams calldata params_) external returns (ISwapper swapper);
}