// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IPrizeHooks } from "pt-v5-vault/interfaces/IPrizeHooks.sol";
import { PrizeVault } from "pt-v5-vault/PrizeVault.sol";
import { PrizeVaultFactory } from "pt-v5-vault/PrizeVaultFactory.sol";
import { Ownable } from "openzeppelin-v5/access/Ownable.sol";
import { SafeERC20, IERC20 } from "openzeppelin-v5/token/ERC20/utils/SafeERC20.sol";

// The max fee value (100 is equal to 1%)
uint256 constant MAX_FEE = 100;

/// @title PoolTogether V5 - Prize Compounding Vault
/// @notice Uses both hook calls to redirect prizes to this contract and swap into prize tokens at a 
/// slight discount. The discount will be awarded to external actors that deposit the accumulated prize
/// tokens back into the prize vault to replenish the prize vault token supply.
/// @dev This contract will hold some liquidity of the prize token and prize vault token in order to 
/// perform swaps. As such, the owner will need to transfer the initial balance of prize vault tokens.
/// Excess funds can be withdrawn at any time by the owner.
/// @dev !!! WARNING !!! This contract has not been audited and is intended for demonstrative use only.
/// @author G9 Software Inc.
contract PrizeCompoundingHook is IPrizeHooks, Ownable {
    using SafeERC20 for IERC20;

    /// @notice Thrown when the configured prize vault is not trusted.
    /// @param prizeVault the prize vault address
    error PrizeVaultNotTrusted(address prizeVault);

    /// @notice Thrown when the prize token address does not match the asset needed to deposit
    /// into the prize vault.
    /// @param prizeToken The prize token address
    /// @param depositAsset The asset needed to deposit into the prize vault
    error PrizeTokenNotDepositAsset(address prizeToken, address depositAsset);

    /// @notice Thrown when the set fee exceeds the max.
    error MaxFeeExceeded(uint256 fee, uint256 maxFee);

    /// @notice Thrown when the caller of a hook is not a trusted prize vault.
    /// @param caller The caller of the hook
    error CallerNotTrustedPrizeVault(address caller);

    /// @notice Thrown when this contract did not receive the prize tokens.
    /// @param prizeRecipient The recipient of the prize tokens
    error DidNotReceivePrize(address prizeRecipient);

    /// @notice Emitted when a prize is successfully compounded.
    /// @param prizeVault The prize vault that called the hook
    /// @param winner The winner of the prize and recipient of the compounded tokens
    /// @param prizeVaultShares The amount of prize vault shares sent to the winner
    /// @param feeAmount The amount of prize tokens kept for recycling rewards
    event PrizeCompounded(address indexed prizeVault, address indexed winner, uint256 prizeVaultShares, uint256 feeAmount);

    /// @notice Emitted when there is not enough prize vault share liquidity to compound the prize.
    /// @param prizeVault The prize vault that called the hook
    /// @param winner The winner of the prize and recipient of the redirected prize tokens
    /// @param prizeAmount The amount of prize tokens redirected to the winner
    /// @param prizeVaultSharesNeeded The amount of prize vault shares that were needed to fulfill the compounding
    /// @param prizeVaultSharesAvailable The amount of prize vault shares that were available at the time
    event NotEnoughLiquidityToCompound(address indexed prizeVault, address indexed winner, uint256 prizeAmount, uint256 prizeVaultSharesNeeded, uint256 prizeVaultSharesAvailable);

    /// @notice Emitted when prize tokens are recycled back into prize vault shares.
    /// @param caller The caller of the function
    /// @param rewardRecipient The recipient of the prize token reward
    /// @param recycleAmount The amount of prize tokens recycled back into the prize vault
    /// @param reward The prize token reward sent to the reward recipient
    event RecyclePrizeTokens(address indexed caller, address indexed rewardRecipient, uint256 recycleAmount, uint256 reward);

    /// @notice Emitted when the owner withdraws a token balance.
    /// @param token The token that was withdrawn
    /// @param recipient The recipient of the token balance
    /// @param amount The amount of tokens withdrawn
    event WithdrawTokenBalance(IERC20 indexed token, address indexed recipient, uint256 amount);

    /// @notice The fee that will be taken from prizes to pay for the swap [0, 100] = [0%, 1%]
    uint256 public immutable fee;

    /// @notice The prize pool token that is sent as prizes
    IERC20 public immutable prizeToken;

    /// @notice The prize vault to compound prizes into
    PrizeVault public immutable prizeVault;

    /// @notice The prize vault factory to use to verify that callers are trusted vaults.
    PrizeVaultFactory public immutable trustedPrizeVaultFactory;

    /// @notice Constructs a new Prize Recycle Hook contract.
    /// @param prizeVault_ The prize vault to compound prizes into
    /// @param trustedPrizeVaultFactory_ The prize vault factory that will be used to verify that callers are trusted vaults.
    /// @param fee_ The percentile fee to take on each swap that will be used to reward external actors that replenish the
    /// prize vault token supply. The fee can vary from 0% to 1% which is defined by the range [0, 100], 100 being 1%.
    constructor(PrizeVault prizeVault_, PrizeVaultFactory trustedPrizeVaultFactory_, uint256 fee_) Ownable(msg.sender) {
        if (fee_ > MAX_FEE) {
            revert MaxFeeExceeded(fee_, MAX_FEE);
        }
        if (!trustedPrizeVaultFactory_.deployedVaults(address(prizeVault_))) {
            revert PrizeVaultNotTrusted(address(prizeVault_));
        }
        fee = fee_;
        trustedPrizeVaultFactory = trustedPrizeVaultFactory_;
        prizeVault = prizeVault_;
        prizeToken = IERC20(address(prizeVault_.prizePool().prizeToken()));
        if (address(prizeToken) != prizeVault_.asset()) {
            revert PrizeTokenNotDepositAsset(address(prizeToken), prizeVault_.asset());
        }
    }

    /// @inheritdoc IPrizeHooks
    /// @dev Redirects prizes to this address
    function beforeClaimPrize(address, uint8, uint32, uint96, address) external view returns (address prizeRecipient, bytes memory data) {
        prizeRecipient = address(this);
    }

    /// @inheritdoc IPrizeHooks
    /// @dev Checks the data to see if we should perform a swap. If so, we exchange the received prize tokens for prize vault
    /// tokens (at a slight discount) and send them to the prize recipient. If there is not enough liquidity, it sends the
    /// prize tokens to the winner instead.
    /// @dev Throws if the caller is not a trusted prize vault.
    function afterClaimPrize(address _winner, uint8, uint32, uint256 _prizeAmount, address _prizeRecipient, bytes memory) external {
        if (!trustedPrizeVaultFactory.deployedVaults(msg.sender)) {
            revert CallerNotTrustedPrizeVault(msg.sender);
        }
        if (_prizeRecipient != address(this)) {
            revert DidNotReceivePrize(_prizeRecipient);
        }

        uint256 _feeAmount = calculateFee(_prizeAmount);
        uint256 _prizeVaultSharePayout = _prizeAmount - _feeAmount;
        uint256 _prizeVaultSharesAvailable = prizeVault.balanceOf(address(this));

        // We only swap if we have enough prize vault tokens for the entire payout. Otherwise, we redirect the prize to the winner.
        if (_prizeVaultSharesAvailable >= _prizeVaultSharePayout) {
            // This contract keeps the prize token fee as incentives for prize vault token refills
            IERC20(address(prizeVault)).safeTransfer(_winner, _prizeVaultSharePayout);
            emit PrizeCompounded(msg.sender, _winner, _prizeVaultSharePayout, _feeAmount);
        } else {
            // No fee is taken since the swap could not be fulfilled
            prizeToken.safeTransfer(_winner, _prizeAmount);
            emit NotEnoughLiquidityToCompound(msg.sender, _winner, _prizeAmount, _prizeVaultSharePayout, _prizeVaultSharesAvailable);
        }
    }

    /// @notice Returns the portion of `_amount` that will be used for fees.
    /// @param _amount The amount of prize tokens
    function calculateFee(uint256 _amount) public view returns(uint256) {
        return (fee * _amount) / MAX_FEE;
    }

    /// @notice Returns the current prize token reward that will be payed out.
    function currentRecycleReward() external view returns(uint256) {
        return calculateFee(prizeToken.balanceOf(address(this)));
    }

    /// @notice Deposits the prize tokens in this contract back into the prize vault and pays the sender a reward.
    /// @dev The reward is equal to the accrued fees.
    /// @return uint256 The prize token reward that will be sent to `_rewardRecipient`
    function recyclePrizeTokens(address _rewardRecipient) external returns(uint256) {
        // calculate the reward and recycle amount
        uint256 _prizeTokenBalance = prizeToken.balanceOf(address(this));
        uint256 _reward = calculateFee(_prizeTokenBalance);
        uint256 _recycleAmount = _prizeTokenBalance - _reward;

        // deposit the recycle amount
        prizeToken.approve(address(prizeVault), _recycleAmount);
        prizeVault.deposit(_recycleAmount, address(this));

        // send the reward to the recipient
        prizeToken.safeTransfer(_rewardRecipient, _reward);

        emit RecyclePrizeTokens(msg.sender, _rewardRecipient, _recycleAmount, _reward);
        return _reward;
    }

    /// @notice Withdraws a token balance to `_recipient`.
    /// @dev Only the owner can withdraw token balances
    /// @param _token The token to withdraw
    /// @param _recipient The recipient of the token
    /// @param _amount The amount of the token to withdraw
    function withdrawTokenBalance(IERC20 _token, address _recipient, uint256 _amount) external onlyOwner() {
        _token.safeTransfer(_recipient, _amount);
        emit WithdrawTokenBalance(_token, _recipient, _amount);
    }
}
