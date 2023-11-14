# Prize Burn Hook

| [Overview](#overview)
| [Design](#design)
| [Implementation](#implementation)
| [Setting the Hook](#setting-the-hook)
|

## Overview

> ⚠️ **WARNING**: This hook should not be used by anyone unless they intentionally want to burn all their prizes. ⚠️

In this prize hook we will demonstrate how to change the recipient of prizes won.

## Design

There are two calls available in a hook: `beforeClaimPrize` and `afterClaimPrize`. As the function names suggest, one is called immediately `before` the prize is claimed and the other is called immediately `after` the prize is claimed. Both functions are passed some parameters regarding the claim such as the winner of the prize, the prize tier, and prize index. In addition, the first hook call (`beforeClaimPrize`) can return an address other than the winner's address to change the recipient of the prize. We will use this functionality to redirect all prizes to the [dEaD address](https://etherscan.io/address/0x000000000000000000000000000000000000dEaD), which is commonly used as an alternative to the zero address to burn tokens.

The design of our hook is straightforward and simple:

```solidity
function beforeClaimPrize(...) external pure returns (address) {
  return address(0x000000000000000000000000000000000000dEaD);
}
```

The implementation disregards the function inputs and returns the `dEaD` address to redirect all prizes to be burned.

## Implementation

#### Import the `IVaultHooks` interface and extend the contract:

```solidity
import { IVaultHooks } from "pt-v5-vault/interfaces/IVaultHooks.sol";

contract PrizeBurnHook is IVaultHooks {
  // hook code goes here...
}
```

#### Implement both hook calls:

```solidity
contract PrizeBurnHook is IVaultHooks {
  function beforeClaimPrize(
    address,
    uint8,
    uint32,
    uint96,
    address
  ) external pure returns (address) {
    return address(0x000000000000000000000000000000000000dEaD);
  }

  function afterClaimPrize(
    address,
    uint8,
    uint32,
    uint256,
    address
  ) external pure {
    /**
     * We don't need any functionality here, but we need to implement an empty function to
     * satisfy the IVaultHooks interface.
     */
  }
}
```

### Done!

You can see the full implementation [here](./PrizeBurnHook.sol).

## Setting the Hook

If a you want to set this hook on a prize vault, you will need to:

1. Deploy the hook contract
2. Call `setHooks` on the prize vault contract with the following information:

```solidity
VaultHooks({
  useBeforeClaimPrize: true;
  useAfterClaimPrize: false;
  implementation: 0x... // replace with the hook deployment contract
});
```
