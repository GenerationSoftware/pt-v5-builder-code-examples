// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { IUniV3Oracle } from "./IUniV3Oracle.sol";

/// @title Uniswap V3 Oracle Factory Interface
/// @author 0xSplits
interface IUniV3OracleFactory {
    function createUniV3Oracle(IUniV3Oracle.InitParams calldata params) external returns (IUniV3Oracle);
}