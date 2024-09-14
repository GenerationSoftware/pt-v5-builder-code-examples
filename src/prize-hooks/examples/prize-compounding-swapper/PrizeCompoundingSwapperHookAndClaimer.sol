// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { PrizeCompoundingSwapperHook, PrizeVault, PrizePool, ISwapper, ISwapperFactory, QuoteParams, QuotePair } from "./PrizeCompoundingSwapperHook.sol";
import { ISwapperFlashCallback } from "./interfaces/ISwapperFlashCallback.sol";
import { IUniV3Oracle } from "./interfaces/IUniV3Oracle.sol";
import { IUniswapV3Router } from "./interfaces/IUniswapV3Router.sol";
import { IUniswapV3PoolImmutables } from "./interfaces/IUniswapV3PoolImmutables.sol";
import { IERC20 } from "openzeppelin-v5/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-v5/token/ERC20/utils/SafeERC20.sol";

/// @title Prize Compounding Swapper Hook and Claimer
/// @notice Extension for the prize compounding swapper hook that adds helpful interfaces for flash
/// swaps and prize claims.
/// @author G9 Software Inc.
contract PrizeCompoundingSwapperHookAndClaimer is PrizeCompoundingSwapperHook, ISwapperFlashCallback {
    using SafeERC20 for IERC20;

    // Constants
    uint32 public constant FACTOR_DENOMINATOR = 1e6; // 100%
    uint32 public constant MAX_CLAIM_REWARD_FACTOR = 0.1e6; // 10% (1e6 is 100%)
    uint32 public constant CLAIM_FALLBACK_TIME_THRESHOLD = 0.75e6; // 75% (claim fallback will start after 75% of draw period)

    // Transient Storage Locations
    bytes32 internal constant REENTRANT_STORAGE_KEY = 0x7cc960b12554423dd9d34a04ec8466d4c702b7fe05d9ad5b104f107dfb9d4674; // keccak256("PrizeCompoundingSwapperHookAndClaimer.Reentrant")
    bytes32 internal constant UNIV3FEE_STORAGE_KEY = 0x6cd635abad6a5f9a689481baa48a89f282b7a6e2f80086c95886517083cfa753; // keccak256("PrizeCompoundingSwapperHookAndClaimer.UniV3Fee")

    /// @notice The uniswap router to use for compounding swaps
    IUniswapV3Router public immutable uniV3Router;

    /// @notice Emitted when a claim reverts
    /// @param vault The vault for which the claim failed
    /// @param tier The tier for which the claim failed
    /// @param winner The winner for which the claim failed
    /// @param prizeIndex The prize index for which the claim failed
    /// @param reason The revert reason
    event ClaimError(
        PrizeVault indexed vault,
        uint8 indexed tier,
        address indexed winner,
        uint32 prizeIndex,
        bytes reason
    );

    /// @notice Emitted during prize compounding when the account does not have a swapper set
    /// @param account The account that does not have a swapper
    event SwapperNotSetForWinner(address indexed account);

    /// @notice Thrown when the min token profit is not met for a flash swap or claim batch
    /// @param actualProfit The actual profit that would have been received
    /// @param minProfit The min profit required
    error MinRewardNotMet(uint256 actualProfit, uint256 minProfit);

    /// @notice Prevents reentrancy to any function with this modifier
    modifier nonReentrant() {
        assembly {
            if tload(REENTRANT_STORAGE_KEY) { revert(0, 0) }
            tstore(REENTRANT_STORAGE_KEY, 1)
        }
        _;
        assembly {
            tstore(REENTRANT_STORAGE_KEY, 0)
        }
    }

    /// @notice Constructor
    /// @param uniV3Router_ The Uniswap V3 router that will be used for compound swaps
    /// @param uniV3Oracle_ The UniV3Oracle that will be used to find underlying asset pricing
    /// @param swapperFactory_ The 0xSplits swapper factory
    /// @param compoundVault_ The prize vault to compound prizes into
    /// @param scaledOfferFactor_ Defines the discount (or premium) of swapper offers
    constructor(
        IUniswapV3Router uniV3Router_,
        IUniV3Oracle uniV3Oracle_,
        ISwapperFactory swapperFactory_,
        PrizeVault compoundVault_,
        uint32 scaledOfferFactor_
    ) PrizeCompoundingSwapperHook(uniV3Oracle_, swapperFactory_, compoundVault_, scaledOfferFactor_) {
        uniV3Router = uniV3Router_;
    }

    /// @notice Claims prizes for winners and auto-compounds if possible.
    /// @param tier The prize tier to claim
    /// @param winners The winners to claim prizes for
    /// @param prizeIndices The prize indices to claim for each winner
    /// @param rewardRecipient Where to send the prize token claim rewards
    /// @param minReward The min reward required for the total claim batch
    /// @return totalReward The total claim rewards collected for the batch
    function claimPrizes(
        uint8 tier,
        address[] calldata winners,
        uint32[][] calldata prizeIndices,
        address rewardRecipient,
        uint256 minReward
    ) external nonReentrant returns (uint256 totalReward) {
        uint256 prizeSize = prizePool.getTierPrizeSize(tier);
        uint256 elapsedTime = block.timestamp - prizePool.drawClosesAt(prizePool.getLastAwardedDrawId());
        uint256 drawPeriod = prizePool.drawPeriodSeconds();
        uint256 normalClaimPeriod = (drawPeriod * CLAIM_FALLBACK_TIME_THRESHOLD) / FACTOR_DENOMINATOR;
        if (prizePool.isCanaryTier(tier)) {
            // Canary claims
            totalReward = _claimPrizes(tier, winners, prizeIndices, uint96(prizeSize));
            prizePool.withdrawRewards(rewardRecipient, totalReward);
        } else if (elapsedTime < normalClaimPeriod) {
            // Normal claims
            _claimPrizes(tier, winners, prizeIndices, 0);
            totalReward = _compoundAccounts(winners, rewardRecipient);
        } else {
            // Fallback claims (no compounding, fee ramps up to max)
            uint32 currentRewardFactor = MAX_CLAIM_REWARD_FACTOR;
            uint32 minRewardFactor = scaledOfferFactor;
            if (minRewardFactor < currentRewardFactor) {
                currentRewardFactor = uint32(
                    minRewardFactor + (
                        (MAX_CLAIM_REWARD_FACTOR - minRewardFactor) * 
                        (elapsedTime - normalClaimPeriod)
                    ) / (drawPeriod - normalClaimPeriod)
                );
            }
            totalReward = _claimPrizes(
                tier,
                winners,
                prizeIndices,
                uint96((prizeSize * currentRewardFactor) / FACTOR_DENOMINATOR)
            );
            prizePool.withdrawRewards(rewardRecipient, totalReward);
        }
        if (totalReward < minReward) {
            revert MinRewardNotMet(totalReward, minReward);
        }
    }

    /// @notice Compounds prizes for the given accounts
    /// @param accounts The account addresses to compound (the depositors)
    /// @param rewardRecipient The recipient of the flash swap rewards
    /// @param minReward The minimum reward required to not revert
    /// @return totalReward The total reward received
    function compoundAccounts(
        address[] calldata accounts,
        address rewardRecipient,
        uint256 minReward
    ) external returns (uint256 totalReward) {
        totalReward = _compoundAccounts(accounts, rewardRecipient);
        if (totalReward < minReward) {
            revert MinRewardNotMet(totalReward, minReward);
        }
    }

    /// @inheritdoc ISwapperFlashCallback
    function swapperFlashCallback(
        address tokenToBeneficiary,
        uint256 amountToBeneficiary,
        bytes calldata /*data*/
    ) external {
        address tokenOut = PrizeVault(tokenToBeneficiary).asset();
        address tokenIn = address(prizePool.prizeToken());
        uniV3Router.exactOutputSingle(
            IUniswapV3Router.ExactOutputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: _uniV3PoolFee(tokenIn, tokenOut),
                recipient: address(this),
                amountOut: amountToBeneficiary,
                amountInMaximum: type(uint256).max,
                sqrtPriceLimitX96: 0
            })
        );
        IERC20(tokenOut).forceApprove(tokenToBeneficiary, amountToBeneficiary);
        PrizeVault(tokenToBeneficiary).deposit(amountToBeneficiary, address(this));
        IERC20(tokenToBeneficiary).forceApprove(msg.sender, amountToBeneficiary);
    }

    /// @notice Claims prizes for a batch of winners and prize indices
    function _claimPrizes(
        uint8 tier,
        address[] calldata winners,
        uint32[][] calldata prizeIndices,
        uint96 rewardPerClaim
    ) internal returns (uint256 totalReward) {
        for (uint256 w = 0; w < winners.length; w++) {
            for (uint256 p = 0; p < prizeIndices[w].length; p++) {
                try
                    compoundVault.claimPrize(winners[w], tier, prizeIndices[w][p], rewardPerClaim, address(this))
                returns (uint256 /* prizeSize */) {
                    totalReward += rewardPerClaim;
                } catch (bytes memory reason) {
                    emit ClaimError(compoundVault, tier, winners[w], prizeIndices[w][p], reason);
                }
            }
        }
    }

    /// @notice Compounds prizes for the given accounts
    function _compoundAccounts(address[] calldata accounts, address rewardRecipient) internal returns (uint256 totalReward) {
        // Build quote params
        address tokenIn = address(prizePool.prizeToken());
        QuoteParams[] memory quoteParams = new QuoteParams[](1);
        quoteParams[0] = QuoteParams({
            quotePair: QuotePair({
                base: tokenIn,
                quote: address(compoundVault)
            }),
            baseAmount: 0,
            data: ""
        });

        // Infinite approve the router to spend `tokenIn`
        IERC20(tokenIn).forceApprove(address(uniV3Router), type(uint256).max);

        // Flash swap for each account
        for (uint256 i = 0; i < accounts.length; i++) {
            address swapper = swappers[accounts[i]];
            if (swapper == address(0)) {
                emit SwapperNotSetForWinner(accounts[i]);
            } else {
                quoteParams[0].baseAmount = uint128(IERC20(tokenIn).balanceOf(swapper));
                ISwapper(swapper).flash(quoteParams, "");
            }
        }

        // Compute rewards
        totalReward = IERC20(tokenIn).balanceOf(address(this));
        if (totalReward > 0) {
            IERC20(tokenIn).safeTransfer(rewardRecipient, totalReward);
        }
    }

    /// @notice Fetches the Uniswap V3 pool fee from the pool that the oracle uses
    function _fetchUniV3PoolFee(address base, address quote) internal view returns (uint24) {
        QuotePair[] memory quotePairs = new QuotePair[](1);
        quotePairs[0] = QuotePair({
            base: base,
            quote: quote
        });
        return IUniswapV3PoolImmutables(
            IUniV3Oracle(address(baseOracle)).getPairDetails(quotePairs)[0].pool
        ).fee();
    }

    /// @notice Returns the Uniswap V3 pool fee from teh pool that the oracle uses
    /// @dev Caches the result in transient storage for cheap, repetitive access
    function _uniV3PoolFee(address base, address quote) internal returns (uint24) {
        uint256 fee;
        assembly {
            fee := tload(UNIV3FEE_STORAGE_KEY)
        }
        if (fee == 0) {
            fee = _fetchUniV3PoolFee(base, quote);
            assembly {
                tstore(UNIV3FEE_STORAGE_KEY, fee)
            }
        }
        return uint24(fee);
    }
}