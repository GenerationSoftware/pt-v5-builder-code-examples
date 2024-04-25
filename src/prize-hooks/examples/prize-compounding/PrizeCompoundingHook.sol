// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IPrizeHooks } from "pt-v5-vault/interfaces/IPrizeHooks.sol";
import { PrizeVault } from "pt-v5-vault/PrizeVault.sol";
import { PrizeVaultFactory } from "pt-v5-vault/PrizeVaultFactory.sol";
import { AccessControl } from "openzeppelin-v5/access/AccessControl.sol";
import { SafeERC20, IERC20 } from "openzeppelin-v5/token/ERC20/utils/SafeERC20.sol";

/// @title PoolTogether V5 - Prize Compounding Vault
/// @notice Uses both hook calls to redirect prizes to this contract and swap into prize tokens at a 
/// slight discount. The discount will be awarded to external actors that deposit the accumulated prize
/// tokens back into the prize vault to replenish the prize vault token supply.
/// @dev This contract will hold some liquidity of the prize token and prize vault token in order to 
/// perform swaps. As such, the owner will need to transfer the initial balance of prize vault tokens.
/// Excess funds can be withdrawn at any time by the owner.
/// @dev Any vaults that are deployed from the trusted vault factory can use this hook, and the admin
/// of the hook can grant other vaults the `TRUSTED_VAULT_ROLE` to add them to the allow list.
/// @dev !!! WARNING !!! This contract has not been audited.
/// @author G9 Software Inc.
contract PrizeCompoundingHook is IPrizeHooks, AccessControl {
    using SafeERC20 for IERC20;

    /// @notice The max fee value (100 is equal to 1%)
    uint256 public constant MAX_FEE = 100;

    /// @notice The fee denominator (equal to 100%)
    uint256 public constant FEE_DENOMINATOR = 10000;

    /// @notice Trusted vault role for access control
    bytes32 public constant TRUSTED_VAULT_ROLE = bytes32(uint256(0x01));

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

    /// @notice The percentage fee that will be taken from prizes and be rewarded to external actors to recycle prize tokens
    /// back into the prize vault [0, 100] = [0%, 1%]
    uint256 public immutable rewardFee;

    /// @notice The percentage fee that will be kept by the hook to compensate the owner for providing liquidity [0, 100] = [0%, 1%]
    uint256 public immutable liquidityFee;

    /// @notice The prize pool token that is sent as prizes
    IERC20 public immutable prizeToken;

    /// @notice The prize vault to compound prizes into
    PrizeVault public immutable prizeVault;

    /// @notice The prize vault factory to use to verify that callers are trusted vaults.
    PrizeVaultFactory public immutable trustedPrizeVaultFactory;

    /// @notice Constructs a new Prize Recycle Hook contract.
    /// @param prizeVault_ The prize vault to compound prizes into
    /// @param trustedPrizeVaultFactory_ The prize vault factory that will be used to verify that callers are trusted vaults.
    /// @param rewardFee_ The percentile fee to take on each swap that will be used to reward external actors that replenish the
    /// prize vault token supply. The fee can vary from 0% to 1% which is defined by the range [0, 100], 100 being 1%.
    /// @param liquidityFee_ The percentile fee to take on each swap that will be kept for the owner as a reward for providing 
    /// liquidity. The fee can vary from 0% to 1% which is defined by the range [0, 100], 100 being 1%.
    /// @dev `rewardFee_` + `liquidityFee_` cannot exceed 1% in total
    /// @dev Sets the sender as the admin of the contract
    constructor(
        PrizeVault prizeVault_,
        PrizeVaultFactory trustedPrizeVaultFactory_,
        uint256 rewardFee_,
        uint256 liquidityFee_
    ) AccessControl() {
        if (rewardFee_ + liquidityFee_ > MAX_FEE) {
            revert MaxFeeExceeded(rewardFee_ + liquidityFee_, MAX_FEE);
        }
        rewardFee = rewardFee_;
        liquidityFee = liquidityFee_;
        trustedPrizeVaultFactory = trustedPrizeVaultFactory_;
        prizeVault = prizeVault_;
        prizeToken = IERC20(address(prizeVault_.prizePool().prizeToken()));
        if (address(prizeToken) != prizeVault_.asset()) {
            revert PrizeTokenNotDepositAsset(address(prizeToken), prizeVault_.asset());
        }
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
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
    /// @dev Throws if the hook did not receive the prize (this happens if the before hook was not called).
    /// @dev Does nothing if the prize amount is zero.
    function afterClaimPrize(address _winner, uint8, uint32, uint256 _prizeAmount, address _prizeRecipient, bytes memory) external {
        if (!isTrustedVault(msg.sender)) {
            revert CallerNotTrustedPrizeVault(msg.sender);
        }
        if (_prizeRecipient != address(this)) {
            revert DidNotReceivePrize(_prizeRecipient);
        }
        if (_prizeAmount > 0) {
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
    }

    /// @notice Returns true if the vault is trusted by this hook.
    /// @param _vault The address of the vault to check
    function isTrustedVault(address _vault) public view returns (bool) {
        return hasRole(TRUSTED_VAULT_ROLE, _vault) || trustedPrizeVaultFactory.deployedVaults(_vault);
    }

    /// @notice Returns the portion of a prize that will be kept for fees.
    /// @param _amount The amount of prize tokens in the prize
    function calculateFee(uint256 _amount) public view returns(uint256) {
        return ((liquidityFee + rewardFee) * _amount) / FEE_DENOMINATOR;
    }

    /// @notice Returns the prize token reward that will be payed out to the recycler.
    /// @param _amount The amount of prize tokens in the hook contract
    function calculateRecycleReward(uint256 _amount) public view returns(uint256) {
        return (rewardFee * _amount) / FEE_DENOMINATOR;
    }

    /// @notice Returns the current reward in prize tokens that will be payed out the the recycler.
    function currentRecycleReward() external view returns (uint256) {
        return calculateRecycleReward(prizeToken.balanceOf(address(this)));
    }

    /// @notice Deposits the prize tokens in this contract back into the prize vault and pays the sender a reward.
    /// @dev The reward is equal to the accrued fees.
    /// @return uint256 The prize token reward that will be sent to `_rewardRecipient`
    function recyclePrizeTokens(address _rewardRecipient) external returns(uint256) {
        // calculate the reward and recycle amount
        uint256 _prizeTokenBalance = prizeToken.balanceOf(address(this));
        uint256 _reward = calculateRecycleReward(_prizeTokenBalance);
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
    function withdrawTokenBalance(IERC20 _token, address _recipient, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _token.safeTransfer(_recipient, _amount);
        emit WithdrawTokenBalance(_token, _recipient, _amount);
    }
}
