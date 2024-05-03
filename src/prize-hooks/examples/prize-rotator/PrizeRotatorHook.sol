// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IPrizeHooks } from "pt-v5-vault/interfaces/IPrizeHooks.sol";
import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";

/// @title PoolTogether V5 - Prize Rotator Hook
/// @notice This prize hook rotates through an array of participants to award all the prizes for each draw
/// to one of the eligible addresses.
/// @dev !!! WARNING !!! This contract has not been audited and is intended for demonstrative use only.
/// @author G9 Software Inc.
contract PrizeRotatorHook is IPrizeHooks {
    PrizePool public immutable prizePool;
    address[] public eligibleAddresses;

    constructor(
        PrizePool prizePool_,
        address[] memory eligibleAddresses_
    ) {
        prizePool = prizePool_;
        eligibleAddresses = eligibleAddresses_;
    }

    function beforeClaimPrize(address,uint8,uint32,uint96,address) external view returns (address prizeRecipient, bytes memory data) {
        uint24 drawId = prizePool.getLastAwardedDrawId();
        prizeRecipient = eligibleAddresses[drawId % eligibleAddresses.length];
    }

    function afterClaimPrize(address, uint8, uint32, uint256, address, bytes memory) external view { }
}
