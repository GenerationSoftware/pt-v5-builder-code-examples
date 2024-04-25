// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IPrizeHooks } from "pt-v5-vault/interfaces/IPrizeHooks.sol";
import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";
import { NUMBER_OF_CANARY_TIERS } from "pt-v5-prize-pool/abstract/TieredLiquidityDistributor.sol";

/// @title PoolTogether V5 - Daily Double Hook
/// @notice Uses both hook calls to redirect daily prizes won back to the prize pool and contribute them on
/// behalf of another vault, thus increasing the chance for bigger wins rather than taking the small wins.
/// @dev !!! WARNING !!! This contract has not been audited and is intended for demonstrative use only.
/// @author G9 Software Inc.
contract DailyDoubleHook is IPrizeHooks {

    /// @notice Thrown if the prize pool address is the zero address.
    error PrizePoolAddressZero();

    /// @notice Thrown if the vault beneficiary address is the zero address.
    error VaultBeneficiaryAddressZero();

    /// @notice Emitted when a daily prize is contributed to the prize pool on behalf of a vault beneficiary
    event ContributedDailyPrize(PrizePool indexed prizePool, address indexed vaultBeneficiary, uint256 amount);

    /// @notice The prize pool to contribute prizes back to.
    PrizePool public immutable prizePool;

    /// @notice The beneficiary of the contributed daily prizes.
    address public immutable vaultBeneficiary;

    /// @notice Constructs a new Daily Double Hook contract.
    /// @param prizePool_ The prize pool that the prizes originate from
    /// @param vaultBeneficiary_ The vault to contribute the daily prizes on behalf of
    constructor(PrizePool prizePool_, address vaultBeneficiary_) {
        if (address(0) == address(prizePool_)) revert PrizePoolAddressZero();
        if (address(0) == vaultBeneficiary_) revert VaultBeneficiaryAddressZero();
        prizePool = prizePool_;
        vaultBeneficiary = vaultBeneficiary_;
    }

    /// @inheritdoc IPrizeHooks
    /// @dev Returns the prize pool address as the prize recipient address if it's a daily prize.
    function beforeClaimPrize(address winner, uint8 tier, uint32, uint96, address) external view returns (address prizeRecipient, bytes memory data) {
        // Only redirect for daily prizes
        if (tier >= prizePool.numberOfTiers() - NUMBER_OF_CANARY_TIERS - 1) {
            prizeRecipient = address(prizePool);
        } else {
            prizeRecipient = winner;
        }
    }

    /// @inheritdoc IPrizeHooks
    /// @dev Contributes the prize amount back to the prize pool on behalf of the specified vault.
    function afterClaimPrize(address, uint8, uint32, uint256 prizeAmount, address prizeRecipient, bytes memory) external {
        if (prizeRecipient == address(prizePool) && prizeAmount > 0) {
            prizePool.contributePrizeTokens(vaultBeneficiary, prizeAmount);
            emit ContributedDailyPrize(prizePool, vaultBeneficiary, prizeAmount);
        }
    }
}
