# Prize Compounding Hook

| [Overview](#overview)
| [Design](#design)
| [Implementation](#implementation)
| [Setting the Hook](#setting-the-hook)
| [Use Cases](#use-cases)
|

## Overview

In this hook example, we'll demonstrate how a custom hook can be used to compound prizes back into a prize vault; automatically increasing the winner's chance to win again.

## Design

To compound wins into more prize assets, our hook contract will act as a 1-sided liquidity pool that swaps prizes at a slight discount with prize vault shares. This discount will then be reserved as a reward for external actors to swap the excess prize tokens back into prize vault shares. This strategy assumes that the prize vault shares we are auto-compounding into are equal in value and decimal precision to the prize token asset.

Since this strategy requires some liquidity to work, a contract admin is set such that they can manage the liquidity to ensure that there will always be enough to compound prizes.

## Implementation

#### Import the `IPrizeHooks` interface and `AccessControl` abstract and extend the contract:

```solidity
import { IPrizeHooks } from "pt-v5-vault/interfaces/IPrizeHooks.sol";
import { AccessControl } from "openzeppelin-v5/access/AccessControl.sol";

contract PrizeCompoundingHook is IPrizeHooks, AccessControl {
  // hook code goes here...
}
```

#### Add a constructor that can be used to set the target prize vault, the fee info, and trusted prize vault factory

```solidity
import { PrizeVault } from "pt-v5-vault/PrizeVault.sol";
import { PrizeVaultFactory } from "pt-v5-vault/PrizeVaultFactory.sol";
import { AccessControl } from "openzeppelin-v5/access/AccessControl.sol";
import { SafeERC20, IERC20 } from "openzeppelin-v5/token/ERC20/utils/SafeERC20.sol";

contract PrizeCompoundingHook is IPrizeHooks {
  using SafeERC20 for IERC20;

  uint256 public constant MAX_FEE = 100;
  uint256 public constant FEE_DENOMINATOR = 10000;

  error MaxFeeExceeded(uint256 fee, uint256 maxFee);
  error PrizeTokenNotDepositAsset(address prizeToken, address depositAsset);

  uint256 public immutable rewardFee;
  uint256 public immutable liquidityFee;
  IERC20 public immutable prizeToken;
  PrizeVault public immutable prizeVault;
  PrizeVaultFactory public immutable trustedPrizeVaultFactory;

  constructor(
    PrizeVault prizeVault_,
    PrizeVaultFactory trustedPrizeVaultFactory_,
    uint256 rewardFee_,
    uint256 liquidityFee_,
    address admin_
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
    _grantRole(DEFAULT_ADMIN_ROLE, admin_);
  }
}
```

> We check that the prize vault accepts deposits of the prize token so we can recycle prize tokens back into prize vault shares by depositing them in the vault.

#### Redirect prizes to this hook:

We can do this by simply returning the hook address from the `beforeClaimPrize` hook function.

```solidity
function beforeClaimPrize(...) external view returns (
  address prizeRecipient,
  bytes memory data
) {
  prizeRecipient = address(this);
}
```

#### Swap prizes to prize vault shares for winners:

After the prize has been transferred to the hook, we do some checks before swapping the prize to prize shares and sending the result to the winner.

It is crucial that we verify that the calling prize vault can be trusted to ensure that the hook is being called in the expected sequence. It is also important that we verify the prize has been transferred to the hook by verifying the `_prizeRecipient` argument in the hook call.

If these checks pass and we have received some non-zero prize value, we will check if the hook has enough liquidity to fulfill the request. If it does, the resulting share value will be sent to the winner and the fee will be kept. In the case that the hook does not have enough liquidity, the original prize value will simply be redirected to the winner to ensure they still get their prize and no fee will be taken.

```solidity
bytes32 public constant TRUSTED_VAULT_ROLE = bytes32(uint256(0x01));

error CallerNotTrustedPrizeVault(address caller);
error DidNotReceivePrize(address prizeRecipient);

event PrizeCompounded(address indexed prizeVault, address indexed winner, uint256 prizeVaultShares, uint256 feeAmount);
event NotEnoughLiquidityToCompound(address indexed prizeVault, address indexed winner, uint256 prizeAmount, uint256 prizeVaultSharesNeeded, uint256 prizeVaultSharesAvailable);

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

    if (_prizeVaultSharesAvailable >= _prizeVaultSharePayout) {
      IERC20(address(prizeVault)).safeTransfer(_winner, _prizeVaultSharePayout);
      emit PrizeCompounded(msg.sender, _winner, _prizeVaultSharePayout, _feeAmount);
    } else {
      prizeToken.safeTransfer(_winner, _prizeAmount);
      emit NotEnoughLiquidityToCompound(msg.sender, _winner, _prizeAmount, _prizeVaultSharePayout, _prizeVaultSharesAvailable);
    }
  }
}

function isTrustedVault(address _vault) public view returns (bool) {
  return hasRole(TRUSTED_VAULT_ROLE, _vault) || trustedPrizeVaultFactory.deployedVaults(_vault);
}

function calculateFee(uint256 _amount) public view returns(uint256) {
  return ((liquidityFee + rewardFee) * _amount) / FEE_DENOMINATOR;
}
```

#### Add a public function to let anyone receive a reward if they recycle the prize tokens back into prize shares:

Sine the fee percentage is immutable, we can be certain that any accrued prize tokens have accumulated the fee portion as a reward for this action. The function can simply deposit the accumulated value minus the reward back into the prize vault and then send the reward to recipient. We reserve the `liquidityFee` portion in the hook contract for the admin to keep.

```solidity
event RecyclePrizeTokens(address indexed caller, address indexed rewardRecipient, uint256 recycleAmount, uint256 reward);

function calculateRecycleReward(uint256 _amount) public view returns(uint256) {
  return (rewardFee * _amount) / FEE_DENOMINATOR;
}

function recyclePrizeTokens(address _rewardRecipient) external returns(uint256) {
  uint256 _prizeTokenBalance = prizeToken.balanceOf(address(this));
  uint256 _reward = calculateRecycleReward(_prizeTokenBalance);
  uint256 _recycleAmount = _prizeTokenBalance - _reward;

  prizeToken.approve(address(prizeVault), _recycleAmount);
  prizeVault.deposit(_recycleAmount, address(this));

  prizeToken.safeTransfer(_rewardRecipient, _reward);

  emit RecyclePrizeTokens(msg.sender, _rewardRecipient, _recycleAmount, _reward);
  return _reward;
}
```

#### Allow the admin to withdraw excess tokens

The admin must manage liquidity in the hook to always ensure that there is enough to auto-compound. As such, they will also need to withdraw these tokens if there is no longer a need for the hook.

Since prize hook calls are atomic and this contract never stores other winner's prizes, there is no risk of the admin having access to token balances other than what they put in plus any accrued rewards.

```solidity
event WithdrawTokenBalance(IERC20 indexed token, address indexed recipient, uint256 amount);

function withdrawTokenBalance(IERC20 _token, address _recipient, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
  _token.safeTransfer(_recipient, _amount);
  emit WithdrawTokenBalance(_token, _recipient, _amount);
}
```

### Done!

You can now automatically compound your prizes into more prize tokens! Check out the full implementation [here](./PrizeCompoundingHook.sol).

## Setting the Hook

If a you want to set this hook on a prize vault, you will need to:

1. Deploy the hook contract
2. Call `setHooks` on the prize vault contract with the following information:

```solidity
VaultHooks({
  useBeforeClaimPrize: true;
  useAfterClaimPrize: true;
  implementation: 0x... // replace with the hook deployment contract
});
```
