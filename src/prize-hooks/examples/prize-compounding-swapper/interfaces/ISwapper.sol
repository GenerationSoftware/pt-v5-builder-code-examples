// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { QuoteParams } from "./IOracle.sol";

/// @title Swapper Interface
/// @author 0xSplits
interface ISwapper {
    function owner() external view returns (address);
    function tokenToBeneficiary() external view returns (address);
    function payback() external payable;
    function transferOwnership(address owner_) external;
    function flash(QuoteParams[] calldata quoteParams_, bytes calldata callbackData_) external returns (uint256);
}