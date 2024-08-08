// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable2Step, Ownable } from "openzeppelin/access/Ownable2Step.sol";
import { Claimable } from "pt-v5-vault/abstract/Claimable.sol";
import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";
import { TwabERC20 } from "pt-v5-vault/TwabERC20.sol";

/// @title PoolTogether V5 - DirectContributor
/// @notice A contract that simulates prize vault behaviour, but with direct contributions only.
/// @dev The owner of this contract can mint new shares and change the permitted claimer.
/// @author G9 Software Inc.
contract DirectContributor is TwabERC20, Claimable, Ownable2Step {

    /// @notice Constructor
    /// @param shareName_ The share token name
    /// @param shareSymbol_ The share token symbol
    /// @param prizePool_ The prize pool to participate in
    /// @param claimer_ The permitted claimer for prizes
    /// @param owner_ The owner of the direct contributor contract
    /// @param initialMintRecipients_ The recipients for the initial share mint
    /// @param initialMintAmounts_ The amount to mint to each respective recipient
    constructor(
        string memory shareName_,
        string memory shareSymbol_,
        PrizePool prizePool_,
        address claimer_,
        address owner_,
        address[] memory initialMintRecipients_,
        uint256[] memory initialMintAmounts_
    ) Claimable(prizePool_, claimer_) TwabERC20(shareName_, shareSymbol_, prizePool.twabController()) Ownable() {
        _transferOwnership(owner_);
        assert(initialMintRecipients_.length == initialMintAmounts_.length);
        for (uint256 i = 0; i < initialMintRecipients_.length; i++) {
            _mint(initialMintRecipients_[i], initialMintAmounts_[i]);
        }
    }

    /// @notice Allows the owner to mint more shares
    function mint(address _to, uint256 _shares) external onlyOwner {
        _mint(_to, _shares);
    }

    /// @notice Allows the owner to set a new claimer
    function setClaimer(address _claimer) external onlyOwner {
        _setClaimer(_claimer);
    }
    
}
