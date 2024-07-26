// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IPrizeHooks } from "pt-v5-vault/interfaces/IPrizeHooks.sol";
import { IERC721 } from "openzeppelin-v5/token/ERC721/IERC721.sol";
import { PrizePool, TwabController } from "pt-v5-prize-pool/PrizePool.sol";
import { UniformRandomNumber } from "uniform-random-number/UniformRandomNumber.sol";

uint256 constant PICK_GAS_ESTIMATE = 60_000; // probably lower, but we set it higher to avoid a reversion

/// @notice Thrown if the boosted vault address is the zero address.
error BoostedVaultAddressZero();

/// @notice Thrown if the prize pool address is the zero address.
error PrizePoolAddressZero();

/// @notice Thrown if the nft collection address is the zero address.
error NftCollectionAddressZero();

/// @notice Thrown if the invalid token ID bounds are provided.
/// @param tokenIdLowerBound The provided lower bound
/// @param tokenIdUpperBound The provided upper bound
error InvalidTokenIdBounds(uint256 tokenIdLowerBound, uint256 tokenIdUpperBound);

/// @title PoolTogether V5 - Hook that boosts prizes on a vault for holders of an NFT collection
/// @notice This prize hook awards the winner's prize to a random holder of a NFT in a specific collection.
/// The winning NFT holder is limited between a specified ID range. The NFT holder must also have some amount
/// of the specified prize vault tokens to be eligible to win. If a winner is picked who does not meet the
/// requirements, the prize will be contributed on behalf of the specified prize vault instead.
/// @dev This contract works best with NFTs that have iterating IDs ex. IDs: (1,2,3,4,5,...)
/// @author G9 Software Inc.
contract NftChanceBoosterHook is IPrizeHooks {

    /// @notice Emitted when a vault is boosted with a prize re-contribution.
    /// @param prizePool The prize pool the vault was boosted on
    /// @param boostedVault The boosted vault
    /// @param prizeAmount The amount of prize tokens contributed
    event BoostedVaultWithPrize(address indexed prizePool, address indexed boostedVault, uint256 prizeAmount);

    /// @notice The ERC721 token whose holders will have a chance to win prizes
    IERC721 public immutable nftCollection;

    /// @notice The prize pool that is awarding prizes
    PrizePool public immutable prizePool;

    /// @notice The twab controller associated with the prize pool
    TwabController public immutable twabController;

    /// @notice The vault that is being boosted
    address public immutable boostedVault;

    /// @notice The minimum TWAB that the selected winner must have to win a prize
    uint256 public immutable minTwabOverPrizePeriod;

    /// @notice The lower bound of eligible NFT IDs (inclusive)
    uint256 public immutable tokenIdLowerBound;

    /// @notice The upper bound of eligible NFT IDs (inclusive)
    uint256 public immutable tokenIdUpperBound;

    /// @notice Constructor to deploy the hook contract
    /// @param nftCollection_ The ERC721 token whose holders will have a chance to win prizes
    /// @param prizePool_ The prize pool that is awarding prizes
    /// @param boostedVault_ The The vault that is being boosted
    /// @param minTwabOverPrizePeriod_ The minimum TWAB that the selected winner must have over the prize
    /// period to win the prize; if set to zero, no balance is needed.
    /// @param tokenIdLowerBound_ The lower bound of eligible NFT IDs (inclusive)
    /// @param tokenIdUpperBound_ The upper bound of eligible NFT IDs (inclusive)
    constructor(
        IERC721 nftCollection_,
        PrizePool prizePool_,
        address boostedVault_,
        uint256 minTwabOverPrizePeriod_,
        uint256 tokenIdLowerBound_,
        uint256 tokenIdUpperBound_
    ) {
        if (address(0) == address(nftCollection_)) revert NftCollectionAddressZero();
        if (address(0) == address(prizePool_)) revert PrizePoolAddressZero();
        if (address(0) == boostedVault_) revert BoostedVaultAddressZero();
        if (tokenIdUpperBound_ < tokenIdLowerBound_) revert InvalidTokenIdBounds(tokenIdLowerBound_, tokenIdUpperBound_);

        nftCollection = nftCollection_;
        prizePool = prizePool_;
        twabController = prizePool_.twabController();
        boostedVault = boostedVault_;
        minTwabOverPrizePeriod = minTwabOverPrizePeriod_;
        tokenIdLowerBound = tokenIdLowerBound_;
        tokenIdUpperBound = tokenIdUpperBound_;
    }

    /// @inheritdoc IPrizeHooks
    /// @dev This prize hook uses the random number from the last awarded prize pool draw to randomly select
    /// the receiver of the prize from a list of current NFT holders. The prize tier and prize index are also
    /// used to provide variance in the entropy for each prize so there can be multiple winners per draw.
    /// @dev Tries to select a winner until the call runs out of gas before reverting to the backup action of 
    /// contributing the prize on behalf of the boosted vault.
    function beforeClaimPrize(address, uint8 _tier, uint32 _prizeIndex, uint96, address) external view returns (address, bytes memory) {
        uint256 _tierStartTime;
        uint256 _tierEndTime;
        uint256 _winningRandomNumber = prizePool.getWinningRandomNumber();
        {
            uint24 _tierEndDrawId = prizePool.getLastAwardedDrawId();
            uint24 _tierStartDrawId = prizePool.computeRangeStartDrawIdInclusive(
                _tierEndDrawId,
                prizePool.getTierAccrualDurationInDraws(_tier)
            );
            _tierStartTime = prizePool.drawOpensAt(_tierStartDrawId);
            _tierEndTime = prizePool.drawClosesAt(_tierEndDrawId);
        }
        uint256 _pickAttempt;
        for (; gasleft() >= PICK_GAS_ESTIMATE; _pickAttempt++) {
            address _ownerOfToken;
            {
                uint256 _randomTokenId;
                uint256 _numTokens = 1 + tokenIdUpperBound - tokenIdLowerBound;
                if (_numTokens == 1) {
                    _randomTokenId = tokenIdLowerBound;
                } else {
                    _randomTokenId = tokenIdLowerBound + UniformRandomNumber.uniform(
                        uint256(keccak256(abi.encode(_winningRandomNumber, _tier, _prizeIndex, _pickAttempt))),
                        _numTokens
                    );
                }
                try nftCollection.ownerOf(_randomTokenId) returns (address _ownerOfResult) {
                    _ownerOfToken = _ownerOfResult;
                } catch { }
            }
            if (_ownerOfToken != address(0)) {
                uint256 _recipientTwab;
                if (minTwabOverPrizePeriod > 0) {
                    _recipientTwab = twabController.getTwabBetween(boostedVault, _ownerOfToken, _tierStartTime, _tierEndTime);
                }
                if (_recipientTwab >= minTwabOverPrizePeriod) {
                    // The owner of the selected NFT wins the prize!
                    return (_ownerOfToken, abi.encode(_pickAttempt));
                }
            }
        }
        // By default, if no NFT winner can be determined, the prize will be sent to the prize pool and
        // contributed on behalf of the boosted prize vault.
        return (address(prizePool), abi.encode(_pickAttempt));
    }

    /// @inheritdoc IPrizeHooks
    /// @dev If the recipient is set to the prize pool, the prize will be contributed on behalf of the vault
    /// that is being boosted. Otherwise, it will do nothing (the prize will have already been sent to the
    /// randomly selected NFT winner).
    function afterClaimPrize(address, uint8, uint32, uint256 _prizeAmount, address _prizeRecipient, bytes memory) external {
        if (_prizeRecipient == address(prizePool) && _prizeAmount > 0) {
            prizePool.contributePrizeTokens(boostedVault, _prizeAmount);
            emit BoostedVaultWithPrize(address(prizePool), boostedVault, _prizeAmount);
        }
    }
}
