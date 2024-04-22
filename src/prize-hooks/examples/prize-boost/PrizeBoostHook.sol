// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IPrizeHooks } from "pt-v5-vault/interfaces/IPrizeHooks.sol";
import { IERC20 } from "openzeppelin-v5/interfaces/IERC20.sol";

/// @title PoolTogether V5 - Prize Boost Vault Hook
/// @notice This contract is a vault hook for PoolTogether V5 that sends additional prize POOL to winners.
/// @author G9 Software Inc.
contract PrizeBoostHook is IPrizeHooks {
    /// @notice Emitted when a prize win is boosted.
    /// @param recipient The recipient of the prize and boost
    /// @param vault The vault the prize was won through
    /// @param boostAmount The amount of boost tokens sent to the recipient
    /// @param tier The prize tier won
    event PrizeBoosted(address indexed recipient, address indexed vault, uint256 boostAmount, uint8 tier);

    /// @notice The vault address that is eligible for the boost.
    address public immutable vault;

    /// @notice The token to send to winners as a boost.
    IERC20 public immutable boostToken;

    /// @notice The amount of boost token to send for each win.
    uint256 public immutable boostAmount;

    /// @notice The max prize tier to boost.
    uint8 public immutable maxTier;

    /// @notice Constructor to set parameters for the vault hook.
    /// @param _vault The vault address that is eligible for the boost
    /// @param _boostToken The token to send to winners as a boost
    /// @param _boostAmount The amount of boost token to send for each win
    /// @param _maxTier The max prize tier to boost
    constructor(address _vault, IERC20 _boostToken, uint256 _boostAmount, uint8 _maxTier) {
        vault = _vault;
        boostToken = _boostToken;
        boostAmount = _boostAmount;
        maxTier = _maxTier;
    }

    /// @inheritdoc IPrizeHooks
    /// @dev This prize hook does not implement the `beforeClaimPrize` call, but it is still required in the
    /// IPrizeHooks interface.
    function beforeClaimPrize(address, uint8, uint32, uint96, address) external pure returns (address, bytes memory) {}

    /// @inheritdoc IPrizeHooks
    /// @notice Sends an additional prize boost to the recipient of a prize if the tier is less than or equal
    /// to the maximum tier to boost.
    /// @dev Fails silently as to not interrupt a prize claim if the prize is not eligible for a boost or if
    /// this contract runs out of boost funds.
    function afterClaimPrize(address, uint8 tier, uint32, uint256, address recipient, bytes memory) external {
        if (msg.sender == vault && tier <= maxTier && boostToken.balanceOf(address(this)) >= boostAmount) {
            boostToken.transfer(recipient, boostAmount);
            emit PrizeBoosted(recipient, vault, boostAmount, tier);
        }
    }
}
