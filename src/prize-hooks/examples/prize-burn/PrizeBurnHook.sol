// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IVaultHooks } from "pt-v5-vault/interfaces/IVaultHooks.sol";

/// @title PoolTogether V5 - Prize Burn Vault Hook
/// @notice This contract is a vault hook for PoolTogether V5 that automatically burns any
/// prizes won.
/// @dev !!! WARNING !!! This contract has not been audited and is intended for demonstrative use only.
/// @dev This hook should not be used as-is by anyone unless they intentionally want to burn all their prizes.
/// @author G9 Software Inc.
contract PrizeBurnHook is IVaultHooks {
    /// @inheritdoc IVaultHooks
    /// @dev This hook returns the dead address as the recipient of the prize so that any prizes won are
    /// immediately burned.
    function beforeClaimPrize(address, uint8, uint32, uint96, address) external pure returns (address) {
        return address(0x000000000000000000000000000000000000dEaD);
    }

    /// @inheritdoc IVaultHooks
    /// @dev This prize hook does not implement the `afterClaimPrize` call, but it is still required in the
    /// IVaultHooks interface.
    function afterClaimPrize(address, uint8, uint32, uint256, address) external pure {}
}
