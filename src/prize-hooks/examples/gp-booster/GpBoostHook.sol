// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IPrizeHooks, PrizeHooks } from "pt-v5-vault/interfaces/IPrizeHooks.sol";
import { Claimable } from "pt-v5-vault/abstract/Claimable.sol";
import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";

/// @title PoolTogether V5 - Grand Prize Booster
/// @notice Uses both hook calls to redirect all prizes won (except the GP) back to the prize pool and contribute them on
/// behalf of this "vault", creating a continuous loop of contributions until this vault's chance slowly fades. The end 
/// result of this hook is to contribute as much capital as possible to the GP without creating a game-able opportunity.
/// @dev If the GP is won by this "vault", the hook will revert any claims, thus forcing the GP value to remain in the
/// prize pool.
/// @dev !!! WARNING !!! This contract has not been audited.
/// @author G9 Software Inc.
contract GpBoostHook is IPrizeHooks, Claimable {

    /// @notice Thrown if the GP is won by this contract
    error LeaveTheGpInThePrizePool();

    /// @notice Emitted when a prize is contributed to the prize pool
    event ContributedPrize(PrizePool indexed prizePool, uint256 amount);

    /// @notice Constructs a new GP Boost Hook
    /// @param prizePool_ The prize pool that the prizes originate from
    /// @param claimer_ The permitted claimer for prizes
    constructor(PrizePool prizePool_, address claimer_) Claimable(prizePool_, claimer_) {
        // Initialize a TWAB for this contract so it can win prizes
        prizePool.twabController().mint(address(this), 1e18);

        // Ensure this contract uses it's own hooks for wins
        _hooks[address(this)] = PrizeHooks({
            useBeforeClaimPrize: true,
            useAfterClaimPrize: true,
            implementation: IPrizeHooks(address(this))
        });
    }

    /// @inheritdoc IPrizeHooks
    /// @dev Returns the prize pool address as the prize recipient address.
    /// @dev Reverts if the prize is the GP.
    function beforeClaimPrize(address winner, uint8 tier, uint32, uint96, address) external view returns (address prizeRecipient, bytes memory data) {
        if (tier == 0) {
            revert LeaveTheGpInThePrizePool();
        } else {
            prizeRecipient = address(prizePool);
        }
    }

    /// @inheritdoc IPrizeHooks
    /// @dev Contributes the prize amount back to the prize pool on behalf of the specified vault.
    function afterClaimPrize(address, uint8, uint32, uint256 prizeAmount, address prizeRecipient, bytes memory) external {
        if (prizeRecipient == address(prizePool) && prizeAmount > 0) {
            prizePool.contributePrizeTokens(address(this), prizeAmount);
            emit ContributedPrize(prizePool, prizeAmount);
        }
    }

    /// @notice Contributes prize tokens to the prize pool on behalf of this contract.
    /// @param amount The amount to contribute
    function contributePrizeTokens(uint256 amount) external {
        prizePool.prizeToken().transferFrom(msg.sender, address(prizePool), amount);
        prizePool.contributePrizeTokens(address(this), amount);
    }
}
