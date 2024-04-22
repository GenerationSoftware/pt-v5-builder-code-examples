// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IPrizeHooks } from "pt-v5-vault/interfaces/IPrizeHooks.sol";
import { IERC721Enumerable } from "openzeppelin/token/ERC721/extensions/IERC721Enumerable.sol";
import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";
import { UniformRandomNumber } from "uniform-random-number/UniformRandomNumber.sol";

/// @notice Thrown if the token does not implement the IERC721Enumerable interface.
error TokenNotERC721Enumerable();

/// @notice Thrown if the prize pool address is the zero address.
error PrizePoolAddressZero();

/// @title PoolTogether V5 - Prize To Enumerable NFT Holder Vault Hook
/// @notice This prize hook awards the winner's prize to a random holder of a NFT in a specific collection.
/// @dev !!! WARNING !!! This contract has not been audited and is intended for demonstrative use only.
/// @author G9 Software Inc.
contract PrizeToEnumerableNFTHolderHook is IPrizeHooks {
    /// @notice The ERC721Enumerable token whose holders will have a chance to win prizes.
    IERC721Enumerable public enumerableToken;

    /// @notice The prize pool that is awarding prizes.
    PrizePool public prizePool;

    /// @notice Constructor to deploy the hook contract.
    /// @param enumerableToken_ The ERC721Enumerable token whose holders will have a chance to win prizes.
    /// @param prizePool_ The prize pool that is awarding prizes.
    constructor(IERC721Enumerable enumerableToken_, PrizePool prizePool_) {
        if (address(0) == address(prizePool_)) revert PrizePoolAddressZero();
        if (!enumerableToken_.supportsInterface(type(IERC721Enumerable).interfaceId)) revert TokenNotERC721Enumerable();

        enumerableToken = enumerableToken_;
        prizePool = prizePool_;
    }

    /// @inheritdoc IPrizeHooks
    /// @dev This prize hook uses the random number from the last awarded prize pool draw to randomly select
    /// the receiver of the prize from a list of current NFT holders. The prize tier and prize index are also
    /// used to provide variance in the entropy for each prize so there can be multiple winners per draw.
    function beforeClaimPrize(address, uint8 tier, uint32 prizeIndex, uint96, address) external view returns (address prizeRecipient, bytes memory data) {
        uint256 _entropy = uint256(keccak256(abi.encode(prizePool.getWinningRandomNumber(), tier, prizeIndex)));
        uint256 _randomTokenIndex = UniformRandomNumber.uniform(_entropy, enumerableToken.totalSupply());
        prizeRecipient = enumerableToken.ownerOf(enumerableToken.tokenByIndex(_randomTokenIndex));
    }

    /// @inheritdoc IPrizeHooks
    /// @dev This prize hook does not implement the `afterClaimPrize` call, but it is still required in the
    /// IPrizeHooks interface.
    function afterClaimPrize(address, uint8, uint32, uint256, address, bytes memory) external pure {}
}
