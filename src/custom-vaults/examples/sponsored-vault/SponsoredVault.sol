// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-v5/interfaces/IERC20.sol";
import { SafeERC20 } from "openzeppelin-v5/token/ERC20/utils/SafeERC20.sol";

import { PrizePool, TwabController } from "pt-v5-prize-pool/PrizePool.sol";
import { TwabERC20 } from "pt-v5-vault/TwabERC20.sol";
import { Claimable } from "pt-v5-vault/abstract/Claimable.sol";

/// @notice Thrown if the asset address is the zero address
error AssetZeroAddress();

/// @title PoolTogether V5 - Sponsored Vault
/// @notice This contract demonstrates a custom vault experience where users deposit an ERC20 token and anyone
/// can sponsor the prize power by donating prize tokens on behalf of the vault.
/// @dev !!! WARNING !!! This contract has not been audited and is intended for demonstrative use only.
/// @author G9 Software Inc.
contract SponsoredVault is TwabERC20, Claimable {
    using SafeERC20 for IERC20;

    /// @notice The asset that the vault accepts as a deposit
    IERC20 public immutable asset;

    /// @notice The constructor to initialize the vault
    /// @param _name The name of the vault token
    /// @param _symbol The symbol of the vault token
    /// @param _asset The token that can be deposited
    /// @param _prizePool The prize pool to contribute to
    /// @param _claimer The address of the claimer contract
    constructor(
        string memory _name,
        string memory _symbol,
        IERC20 _asset,
        PrizePool _prizePool,
        address _claimer
    ) TwabERC20(_name, _symbol, _prizePool.twabController()) Claimable(_prizePool, _claimer) {
        if (address(0) == address(_asset)) revert AssetZeroAddress();
        asset = _asset;
    }

    /// @notice Sponsors the vault by contributing prize tokens to the prize pool.
    /// @param _amount The amount of prize tokens to contribute
    function donatePrizeTokens(uint256 _amount) external {
        IERC20(address(prizePool.prizeToken())).safeTransferFrom(msg.sender, address(prizePool), _amount);
        prizePool.contributePrizeTokens(address(this), _amount);
    }

    /// @notice Deposits asset tokens and mints the vault balance.
    /// @param _amount The amount to deposit
    function deposit(uint256 _amount) external {
        asset.safeTransferFrom(msg.sender, address(this), _amount);
        _mint(msg.sender, _amount);
    }

    /// @notice Withdraws asset tokens and burns the vault balance.
    /// @param _amount The amount to withdraw
    function withdraw(uint256 _amount) external {
        _burn(msg.sender, _amount);
        asset.safeTransfer(msg.sender, _amount);
    }
}
