# Prize Recycle Hook

| [Overview](#overview)
| [Design](#design)
| [Implementation](#implementation)
| [Setting the Hook](#setting-the-hook)
| [Use Cases](#use-cases)
|

## Overview

In this hook example, we'll demonstrate how a custom hook can be used to contribute prizes won back into the prize pool on behalf of the vault.

## Design

To contribute prizes back to the prize pool, we will need a 2 step approach:

1. Redirect prizes to be sent to the prize pool instead of the winner.
2. Contribute the prizes on behalf of the vault after the prizes have been claimed.

We can accomplish the first step by using the `beforeClaimPrize` hook call to redirect prizes to the prize pool address. Then, when the `afterClaimPrize` hook is called, the prize tokens will already be in the custody of the prize pool, so we can contribute them on behalf of the vault.

## Implementation

#### Import the `IVaultHooks` interface and extend the contract:

```solidity
import { IVaultHooks } from "pt-v5-vault/interfaces/IVaultHooks.sol";

contract PrizeRecycleHook is IVaultHooks {
  // hook code goes here...
}
```

#### Add a constructor that can be used to set the prize pool address:

```solidity
import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";

error PrizePoolAddressZero();

contract PrizeRecycleHook is IVaultHooks {
  PrizePool public prizePool;

  constructor(PrizePool prizePool_) {
    if (address(0) == address(prizePool_)) revert PrizePoolAddressZero();
    prizePool = prizePool_;
  }
}
```

#### Redirect prizes to the prize pool:

We can do this by simply returning the prize pool address from the `beforeClaimPrize` hook function.

```solidity
function beforeClaimPrize(...) external view returns (address) {
  return address(prizePool);
}
```

#### Contribute prize value on behalf of the vault:

Vaults participate in the prize pool by sending POOL tokens to the contract and immediately calling the `contributePrizeTokens` function after. Since we redirected the prizes to be sent to the prize pool in the previous hook call, we can now contribute them on behalf of the vault in the second call. This is only possible since the hooks are called in the same transaction (`beforeClaimPrize` -> `claimPrize` -> `afterClaimPrize`). If they weren't called atomically, there would be a race condition in between the moment when the prize is transferred to the prize pool and the moment that the `contributePrizeTokens` function is called.

> Note: If you wanted to only donate a portion of the prize back to the prize pool, you could redirect the prize to be sent to this contract and then handle the prize division in this hook before sending the remainder back to your address.

```solidity
function afterClaimPrize(...) external {
  uint256 _balance = prizePool.prizeToken().balanceOf(address(prizePool));
  prizePool.contributePrizeTokens(msg.sender, _balance);
}
```

Note that we contribute the prize tokens on behalf of the `msg.sender` address. Since the vault is calling these hooks, this address will be the vault's address and the tokens will be contributed on it's behalf. If you wanted to contribute the tokens on behalf of a different vault, you could do so by changing the address in the `contributePrizeTokens` function call.

### Done!

You can now automatically donate your prizes back to the prize pool without delegating any funds! See the full implementation [here](./PrizeRecycleHook.sol).

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

## Use Cases

There are already many ways to "donate" prize power to vaults such as sponsoring the vault, or delegating to a subset of addresses, and this hook is just an alternate way to do accomplish this; however, there are still some unique use cases where this hook could be useful. For example, you could use the hook to bootstrap prize power on a new vault that doesn't have a lot of liquidity. By setting this hook on a vault that wins consistent prizes, but redirecting the prizes your address wins to the new vault instead, the prizes would be used to boost the prize power of the new vault without having to setup and maintain a `VaultBooster` contract.
