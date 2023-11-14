// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IVaultHooks } from "pt-v5-vault/interfaces/IVaultHooks.sol";
import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";
import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";

/// @notice Thrown if the target mint per day is zero.
error TargetMintPerDayZero();

/// @notice Thrown if the prize pool address is the zero address.
error PrizePoolAddressZero();

/// @notice Thrown if the prize pool has not awarded a prize to the proclaimed winner.
/// @param vault The vault that is calling the hook
/// @param winner The winner of the prize
/// @param tier The prize tier
/// @param prizeIndex The index of the prize
error DidNotWin(address vault, address winner, uint8 tier, uint32 prizeIndex);

/// @title PoolTogether V5 - Prize Pixel Vault Hook
/// @notice This contract mints Prize Pixel tokens at a target daily rate to winners in PoolTogether V5.
/// @dev !!! WARNING !!! This contract has not been audited and is intended for demonstrative use only.
/// @author G9 Software Inc.
contract PrizePixelHook is ERC20, IVaultHooks {
    /// @notice Emitted when a prize recipient wins prize pixels.
    /// @param recipient The address of the recipient of the prize pixel tokens
    /// @param tokensPerWinner The number of prize pixel tokens won
    /// @param winner The address of the prize winner
    /// @param tier The winning tier
    /// @param prizeIndex The winning prize index
    event WonPrizePixels(
        address indexed recipient,
        uint256 tokensPerWinner,
        address indexed winner,
        uint8 indexed tier,
        uint32 prizeIndex
    );

    /// @notice The target number of Prize Pixel tokens to mint to winners per day (actual results will vary slightly).
    /// @dev This value is used as a target daily mint rate in the prize hook so the contract can keep the supply rate
    /// stable even if the number of daily prizes go up.
    uint256 public targetMintPerDay;

    /// @notice The prize pool to retrieve prize odds from.
    PrizePool public prizePool;

    /// @notice Constructor to deploy a new prize pixel hook.
    /// @param targetMintPerDay_ The target number of tokens to mint per day.
    /// @param prizePool_ The prize pool that is awarding prizes.
    constructor(uint256 targetMintPerDay_, PrizePool prizePool_) ERC20("Prize Pixel", "PrizePixel") {
        if (0 == targetMintPerDay_) revert TargetMintPerDayZero();
        if (address(0) == address(prizePool_)) revert PrizePoolAddressZero();

        targetMintPerDay = targetMintPerDay_;
        prizePool = prizePool_;
    }

    /// @inheritdoc IVaultHooks
    /// @dev This prize hook does not implement the `beforeClaimPrize` call, but it is still required in the
    /// IVaultHooks interface.
    function beforeClaimPrize(address, uint8, uint32, uint96, address) external pure returns (address) {}

    /// @inheritdoc IVaultHooks
    /// @dev If the prize tier is the current daily prize, the recipient will have a chance to win prize pixels
    /// as well. This is determined by the prize index. All winners that have a prize index lower than the
    /// target mint per day will split the daily prize pixels.
    /// @dev The prize win is verified on the prize pool before minting any tokens. If it is a false claim, this
    /// function will revert.
    function afterClaimPrize(address winner, uint8 tier, uint32 prizeIndex, uint256, address recipient) external {
        // Verify the prize and vault by checking the prize pool
        if (!prizePool.isWinner(msg.sender, winner, tier, prizeIndex))
            revert DidNotWin(msg.sender, winner, tier, prizeIndex);

        // We only award prize pixels to the current daily prize winners with a prize index less than the target
        // number of pixels minted per day.
        if (tier == prizePool.numberOfTiers() - 2 && prizeIndex < targetMintPerDay) {
            uint32 _estimatedNumberOfPrizes = prizePool.getTierPrizeCount(tier);
            uint256 tokensPerWinner = 1;
            if (_estimatedNumberOfPrizes < targetMintPerDay) {
                tokensPerWinner = targetMintPerDay / _estimatedNumberOfPrizes;
            }

            emit WonPrizePixels(recipient, tokensPerWinner, winner, tier, prizeIndex);
            _mint(recipient, tokensPerWinner);
        }
    }
}
