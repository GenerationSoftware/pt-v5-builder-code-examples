// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20 } from "openzeppelin/interfaces/IERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";

import { PrizePool, TwabController } from "pt-v5-prize-pool/PrizePool.sol";
import { IClaimable } from "pt-v5-claimable-interface/interfaces/IClaimable.sol";

/// @notice Thrown if the asset address is the zero address
error AssetZeroAddress();

/// @notice Thrown if the prize pool is the zero address
error PrizePoolZeroAddress();

/// @notice Thrown if the claimer is the zero address
error ClaimerZeroAddress();

/// @notice Thrown if the caller of `claimPrize` is not the claimer
/// @param caller The calling address
/// @param claimer The claimer address
error CallerNotClaimer(address caller, address claimer);

/// @title PoolTogether V5 - Sponsored Vault
/// @notice This contract demonstrates a custom vault experience where users deposit an ERC20 token and anyone
/// sponsors the prize power by donating prize tokens on behalf of the vault.
/// @dev !!! WARNING !!! This contract has not been audited and is intended for demonstrative use only.
/// @author G9 Software Inc.
contract SponsoredVault is IClaimable {
    using SafeERC20 for IERC20;

    /// @notice The prize pool to contribute to
    PrizePool public immutable prizePool;

    /// @notice The TWAB controller to use for vault balances
    TwabController public immutable twabController;

    /// @notice The asset that the vault accepts as a deposit
    IERC20 public immutable asset;

    /// @notice The address of the claimer contract
    address public immutable claimer;

    /// @notice The constructor to initialize the vault
    /// @param _asset The token that can be deposited
    /// @param _prizePool The prize pool to contribute to
    /// @param _claimer The address of the claimer contract
    constructor(IERC20 _asset, PrizePool _prizePool, address _claimer) {
        if (address(0) == address(_asset)) revert AssetZeroAddress();
        if (address(0) == address(_prizePool)) revert PrizePoolZeroAddress();
        if (address(0) == _claimer) revert ClaimerZeroAddress();
        prizePool = _prizePool;
        twabController = _prizePool.twabController();
        asset = _asset;
        claimer = _claimer;
    }

    /// @inheritdoc IClaimable
    function claimPrize(
        address _winner,
        uint8 _tier,
        uint32 _prizeIndex,
        uint96 _fee,
        address _feeRecipient
    ) external returns (uint256) {
        if (claimer != msg.sender) {
            revert CallerNotClaimer(msg.sender, claimer);
        }
        return prizePool.claimPrize(_winner, _tier, _prizeIndex, _winner, _fee, _feeRecipient);
    }

    /// @notice Sponsors the vault by contributing prize tokens to the prize pool.
    /// @param _amount The amount of prize tokens to contribute
    function donatePrizeTokens(uint256 _amount) external {
        prizePool.prizeToken().safeTransferFrom(msg.sender, address(prizePool), _amount);
        prizePool.contributePrizeTokens(address(this), _amount);
    }

    /// @notice Deposits asset tokens and mints the vault balance.
    /// @param _amount The amount to deposit
    function deposit(uint256 _amount) external {
        asset.safeTransferFrom(msg.sender, address(this), _amount);
        twabController.mint(msg.sender, SafeCast.toUint96(_amount));
    }

    /// @notice Withdraws asset tokens and burns the vault balance.
    /// @param _amount The amount to withdraw
    function withdraw(uint256 _amount) external {
        twabController.burn(msg.sender, SafeCast.toUint96(_amount));
        asset.transfer(msg.sender, _amount);
    }

    /// @notice Returns the amount deposited for the given account.
    /// @param _account The address of the account to get the balance of
    /// @return The balance of the account denoted in asset tokens
    function balanceOf(address _account) external view returns (uint256) {
        return twabController.balanceOf(address(this), _account);
    }
}
