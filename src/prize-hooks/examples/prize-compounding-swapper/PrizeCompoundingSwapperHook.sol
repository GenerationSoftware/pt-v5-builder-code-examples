// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { PrizeVault } from "pt-v5-vault/PrizeVault.sol";
import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";
import { NUMBER_OF_CANARY_TIERS } from "pt-v5-prize-pool/abstract/TieredLiquidityDistributor.sol";
import { IPrizeHooks } from "pt-v5-vault/interfaces/IPrizeHooks.sol";
import { IOracle, QuoteParams, QuotePair } from "./interfaces/IOracle.sol";
import { ISwapper } from "./interfaces/ISwapper.sol";
import { ISwapperFactory, CreateSwapperParams, OracleParams, CreateOracleParams, SetPairScaledOfferFactorParams } from "./interfaces/ISwapperFactory.sol";

// The approximate denominator of the next daily prize size compared to the current daily prize
// size if the prize pool goes up in tiers.
uint256 constant NEXT_TIER_DAILY_PRIZE_DENOMINATOR = 8;

/// @title PoolTogether V5 - Prize Compounding Swapper Hook
/// @notice Uses the 0xSplits Swapper contract factory to let users create their own swappers
/// that will receive any prizes won through this hook. External actors can then swap winnings
/// to the `compoundVault` asset specified by this hook which is forwarded back to the winner.
/// The winner can also use this hook to vote on minimum prize sizes by specifying a prize amount
/// denominated in the `compoundVault` asset that is used to influence the prize pool tiers.
/// @author G9 Software Inc.
contract PrizeCompoundingSwapperHook is IPrizeHooks, IOracle {

    /// @notice The underlying oracle to pull asset prices from
    IOracle public immutable baseOracle;

    /// @notice The swapper factory to create new swappers from
    ISwapperFactory public immutable swapperFactory;

    /// @notice The vault to compound to
    PrizeVault public immutable compoundVault;

    /// @notice The scaled offer factor that is used for swaps (1e6 is 100%, over is premium to oracle, 
    /// under is discount to oracle)
    uint32 public immutable scaledOfferFactor;

    /// @notice The prize pool associated with the prize vault
    PrizePool public immutable prizePool;

    /// @notice Mapping of accounts to swappers.
    mapping(address account => address swapper) public swappers;

    /// @notice Mapping of accounts to minimum desired prize size denominated in `compoundVault` tokens.
    mapping(address account => uint256 minDesiredPrizeSize) public prizeSizeVotes;

    /// @notice Emitted when an account sets a new swapper.
    /// @param account The account setting the swapper
    /// @param newSwapper The new swapper address
    /// @param previousSwapper The previous swapper address
    event SetSwapper(address indexed account, address indexed newSwapper, address indexed previousSwapper);

    /// @notice Emitted when an account votes for a minimum desired prize size.
    /// @param account The account voting
    /// @param minDesiredPrizeSize The minimum desired prize size denominated in `compoundVault` tokens
    event SetPrizeSizeVote(address indexed account, uint256 minDesiredPrizeSize);

    /// @notice Thrown when the winning account votes against the current number of prize tiers.
    /// @param currentNumTiers The current number of tiers
    /// @param dailyPrizeSize The current daily prize size (denominated in `compoundVault` tokens)
    /// @param minDesiredPrizeSize The minimum desired prize size (denominated in `compoundVault` tokens)
    error VoteToLowerPrizeTiers(uint8 currentNumTiers, uint256 dailyPrizeSize, uint256 minDesiredPrizeSize);

    /// @notice Thrown when the winning account votes against going up in prize tiers, but is satisfied with staying
    /// at the current number of tiers.
    /// @param currentNumTiers The current number of tiers
    /// @param dailyPrizeSize The current daily prize size (denominated in `compoundVault` tokens)
    /// @param minDesiredPrizeSize The minimum desired prize size (denominated in `compoundVault` tokens)
    error VoteToStayAtCurrentPrizeTiers(uint8 currentNumTiers, uint256 dailyPrizeSize, uint256 minDesiredPrizeSize);
    
    /// @notice Constructor
    /// @param baseOracle_ The oracle that will be used to find underlying asset pricing
    /// @param swapperFactory_ The 0xSplits swapper factory
    /// @param compoundVault_ The prize vault to compound prizes into
    /// @param scaledOfferFactor_ Defines the discount (or premium) of swapper offers
    constructor(
        IOracle baseOracle_,
        ISwapperFactory swapperFactory_,
        PrizeVault compoundVault_,
        uint32 scaledOfferFactor_
    ) {
        baseOracle = baseOracle_;
        swapperFactory = swapperFactory_;
        compoundVault = compoundVault_;
        scaledOfferFactor = scaledOfferFactor_;
        prizePool = compoundVault_.prizePool();
    }

    /// @notice Creates a new swapper for the caller and sets prizes to be redirected to their swapper.
    /// @dev If the caller already has a swapper set, this call does nothing and returns the existing swapper.
    /// @return The swapper that is set for the caller
    function setSwapper() public returns (ISwapper) {
        address _currentSwapper = swappers[msg.sender];
        if (_currentSwapper != address(0)) {
            return ISwapper(_currentSwapper);
        } else {
            ISwapper _swapper = swapperFactory.createSwapper(
                CreateSwapperParams({
                    owner: address(this),
                    paused: false,
                    beneficiary: msg.sender,
                    tokenToBeneficiary: address(compoundVault),
                    oracleParams: OracleParams({
                        oracle: this,
                        createOracleParams: CreateOracleParams(address(0), "")
                    }),
                    defaultScaledOfferFactor: scaledOfferFactor,
                    pairScaledOfferFactors: new SetPairScaledOfferFactorParams[](0)
                })
            );
            emit SetSwapper(msg.sender, address(_swapper), _currentSwapper);
            swappers[msg.sender] = address(_swapper);
            return _swapper;
        }
    }

    /// @notice Sets the account minimum prize size vote.
    /// @param minDesiredPrizeSize The account's minimum desired prize size denominated in `compoundVault` tokens
    function setPrizeSizeVote(uint256 minDesiredPrizeSize) public {
        prizeSizeVotes[msg.sender] = minDesiredPrizeSize;
        emit SetPrizeSizeVote(msg.sender, minDesiredPrizeSize);
    }

    /// @notice Sets the swapper and prize size vote for the account in one transaction.
    /// @param minDesiredPrizeSize The account's minimum desired prize size denominated in `compoundVault` tokens
    function setPrizeSizeVoteAndSwapper(uint256 minDesiredPrizeSize) external {
        setPrizeSizeVote(minDesiredPrizeSize);
        setSwapper();
    }

    /// @notice Transfers ownership of the caller's swapper to the caller's address. This is useful if
    /// tokens get stuck in the caller's swapper that need to be recovered.
    /// @dev Resets the caller's set swapper to the zero address.
    /// @return The recovered swapper address (if any)
    function removeAndRecoverSwapper() external returns (address) {
        address _previousSwapper = swappers[msg.sender];
        if (_previousSwapper != address(0)) {
            ISwapper(_previousSwapper).transferOwnership(msg.sender);
            delete swappers[msg.sender];
            emit SetSwapper(msg.sender, address(0), _previousSwapper);
        }
        return _previousSwapper;
    }

    /// @inheritdoc IOracle
    /// @dev Remaps the quote token addresses to the underlying 4626 `asset` if supported before passing
    /// the quote call to the base oracle.
    /// @dev THIS ENFORCES THAT THE 4626 TOKEN HAS A ONE-TO-ONE CONVERSION WITH THE UNDERLYING ASSET.
    /// @dev Fails if the oracle has a `sequencerFeed` with an invalid round. This enables backwards compatibility 
    /// with old 0xSplits oracles.
    function getQuoteAmounts(QuoteParams[] memory quoteParams) public view returns (uint256[] memory) {
        for (uint256 i; i < quoteParams.length; i++) {
            try PrizeVault(quoteParams[i].quotePair.quote).asset() returns (address _asset) {
                assert(PrizeVault(quoteParams[i].quotePair.quote).convertToAssets(1) == 1);
                quoteParams[i].quotePair.quote = _asset;
            } catch {
                // nothing
            }
        }
        (bool _success, bytes memory _tempData) = address(baseOracle).staticcall(abi.encodeWithSignature("sequencerFeed()"));
        if (_success) {
            address _sequencer = abi.decode(_tempData, (address));
            (_success, _tempData) = _sequencer.staticcall(abi.encodeWithSignature("latestRoundData()"));
            assert(_success);
            (,,uint256 startedAt,,) = abi.decode(_tempData, (uint80,int256,uint256,uint256,uint80));
            assert(startedAt != 0); // invalid round
        }
        return baseOracle.getQuoteAmounts(quoteParams);
    }

    /// @inheritdoc IPrizeHooks
    /// @dev Maps the winner address to their defined swapper contract and redirects the prize there.
    /// @dev If no swapper exists for the winner, the recipient will be set to the winner address.
    /// @dev If the winner has voted on a minimum prize size, this hook will revert certain canary claims
    /// to influence the prize size based on the vote.
    function beforeClaimPrize(address _winner, uint8 _tier, uint32, uint96, address) external view returns (address prizeRecipient, bytes memory data) {
        uint256 _minDesiredPrizeSize = prizeSizeVotes[_winner];
        if (_minDesiredPrizeSize > 0) {

            // If the tier is a canary tier, determine if the account will vote against it
            uint8 _numberOfTiers = prizePool.numberOfTiers();
            if (_tier >= _numberOfTiers - NUMBER_OF_CANARY_TIERS) {
                uint128 _dailyPrizeSize = prizePool.getTierPrizeSize(_numberOfTiers - NUMBER_OF_CANARY_TIERS - 1);
                QuoteParams[] memory _quoteParams = new QuoteParams[](1);
                _quoteParams[0] = QuoteParams({
                    quotePair: QuotePair({
                        base: address(prizePool.prizeToken()),
                        quote: address(compoundVault)
                    }),
                    baseAmount: _dailyPrizeSize,
                    data: ""
                });
                try this.getQuoteAmounts(_quoteParams) returns (uint256[] memory _convertedPrizeSize) {
                    if (_convertedPrizeSize[0] < _minDesiredPrizeSize) {
                        revert VoteToLowerPrizeTiers(_numberOfTiers, _convertedPrizeSize[0], _minDesiredPrizeSize);
                    } else if (_tier == _numberOfTiers - 1 && _convertedPrizeSize[0] / NEXT_TIER_DAILY_PRIZE_DENOMINATOR < _minDesiredPrizeSize) {
                        revert VoteToStayAtCurrentPrizeTiers(_numberOfTiers, _convertedPrizeSize[0], _minDesiredPrizeSize);
                    }
                } catch {
                    // The oracle failed, so we will abstain voting for this claim
                    data = "vote-abstained";
                }
            }
        }

        // Set the prize recipient
        address _swapper = swappers[_winner];
        if (_swapper == address(0)) {
            prizeRecipient = address(_winner);
        } else {
            prizeRecipient = _swapper;
        }
    }

    /// @inheritdoc IPrizeHooks
    /// @dev Does nothing, but is still required by the interface.
    function afterClaimPrize(address, uint8, uint32, uint256, address, bytes memory) external { }
}