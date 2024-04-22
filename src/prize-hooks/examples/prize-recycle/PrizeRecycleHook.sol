// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IPrizeHooks } from "pt-v5-vault/interfaces/IPrizeHooks.sol";
import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";

/// @notice Thrown if the prize pool address is the zero address.
error PrizePoolAddressZero();

/// @title PoolTogether V5 - Prize Recycle Vault Hook
/// @notice Uses both hook calls to redirect prizes won back to the prize pool and contribute them on
/// behalf of the vault.
/// @dev !!! WARNING !!! This contract has not been audited and is intended for demonstrative use only.
/// @author G9 Software Inc.
contract PrizeRecycleHook is IPrizeHooks {
    /// @notice The prize pool to contribute prizes back to.
    PrizePool public prizePool;

    /// @notice Constructs a new Prize Recycle Hook contract.
    /// @param prizePool_ The prize pool that the prizes originate from
    constructor(PrizePool prizePool_) {
        if (address(0) == address(prizePool_)) revert PrizePoolAddressZero();
        prizePool = prizePool_;
    }

    /// @inheritdoc IPrizeHooks
    /// @dev Returns the prize pool address as the prize recipient address.
    function beforeClaimPrize(address, uint8, uint32, uint96, address) external view returns (address prizeRecipient, bytes memory data) {
        prizeRecipient = address(prizePool);
    }

    /// @inheritdoc IPrizeHooks
    /// @dev Contributes the prize amount back to the prize pool on behalf of the vault.
    function afterClaimPrize(address, uint8, uint32, uint256, address, bytes memory) external {
        uint256 _balance = prizePool.prizeToken().balanceOf(address(prizePool));
        prizePool.contributePrizeTokens(msg.sender, _balance);
    }
}
