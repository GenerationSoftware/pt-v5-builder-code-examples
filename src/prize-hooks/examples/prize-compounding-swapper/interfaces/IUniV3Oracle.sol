// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { IOracle, QuotePair } from "./IOracle.sol";

/// @title Uniswap V3 Oracle Interface
/// @author 0xSplits
interface IUniV3Oracle is IOracle {

    struct InitParams {
        address owner;
        bool paused;
        uint32 defaultPeriod;
        SetPairDetailParams[] pairDetails;
    }

    struct SetPairDetailParams {
        QuotePair quotePair;
        PairDetail pairDetail;
    }

    struct PairDetail {
        address pool;
        uint32 period;
    }

    function getPairDetails(QuotePair[] calldata quotePairs) external view returns (PairDetail[] memory pairDetails);
}