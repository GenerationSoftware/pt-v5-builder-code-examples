# Prize Boost Hook

| [Overview](#overview)
| [Design](#design)
| [Implementation](#implementation)
| [Setting the Hook](#setting-the-hook)
| [Use Cases](#use-cases)
|

## Overview

In this hook example, we'll demonstrate how a custom hook can be used to boost prizes on a specific vault.

## Design

To boost a prize, our hook contract will need to hold some boost tokens and then distribute them in the `afterClaimPrize` call to prize winners. We can also set a max eligible tier so that people can't easily game the system by claiming normally unprofitable canary prize wins. When the hook is called, it will check to see that the prize meets the tier requirements and that the hook contract holds enough boost tokens before sending a preset boost amount to the prize recipient.

## Implementation

#### Import the `IPrizeHooks` interface and extend the contract:

```solidity
import { IPrizeHooks } from "pt-v5-vault/interfaces/IPrizeHooks.sol";

contract PrizeBoostHook is IPrizeHooks {
  // hook code goes here...
}
```

#### Add a constructor that can be used to set the boost information:

```solidity
import { IERC20 } from "openzeppelin/interfaces/IERC20.sol";

// ...

address public immutable vault;
IERC20 public immutable boostToken;
uint256 public immutable boostAmount;
uint8 public immutable maxTier;

constructor(address _vault, IERC20 _boostToken, uint256 _boostAmount, uint8 _maxTier) {
  vault = _vault;
  boostToken = _boostToken;
  boostAmount = _boostAmount;
  maxTier = _maxTier;
}
```

We set the vault that is eligible for prize boosts, the boost token that will be distributed, and the boost amount that will be sent each time an eligible prize is won. The max eligible tier is also set to allow additional configuration.

#### Implement the hook functions:

```solidity
event PrizeBoosted(address indexed recipient, address indexed vault, uint256 boostAmount, uint8 tier);

function beforeClaimPrize(address, uint8, uint32, uint96, address) external pure returns (address) {
  // We don't use this hook call, so we do nothing
}

function afterClaimPrize(address, uint8 tier, uint32, uint256, address recipient) external {
  if (msg.sender == vault && tier <= maxTier && boostToken.balanceOf(address(this)) >= boostAmount) {
    boostToken.transfer(recipient, boostAmount);
    emit PrizeBoosted(recipient, vault, boostAmount, tier);
  }
}
```

> Note that we check if the sender is the vault address. This is the simplest way to verify that a prize has actually been won by the recipient, but only works if the vault was deployed through the standard vault factory or supports the same prize hooks.

In the `afterClaimPrize` call, we check if the prize is valid and if the hook contract has enough boost tokens to transfer before sending the boost to the recipient. If any conditions fail, the hook will simply do nothing instead of reverting. This is to ensure that the depositor still receives their normal prize, even if the boost is no longer running. If the hook reverted, the entire prize claim would revert as well, and it would be impossible for a depositor to receive their prize until they removed the hook.

### Done!

You can now automatically boost prizes on a vault by distributing additional tokens! See the full implementation [here](./PrizeBoostHook.sol).

## Setting the Hook

If a you want to set this hook on a prize vault, you will need to:

1. Deploy the hook contract
2. Call `setHooks` on the prize vault contract with the following information:

```solidity
VaultHooks({
  useBeforeClaimPrize: false;
  useAfterClaimPrize: true;
  implementation: 0x... // replace with the hook deployment contract
});
```

## Use Cases

There are already multiple ways to boost a vault's winning chances by contributing to the prize pool on behalf of the vault, or by using a [Vault Booster](https://github.com/GenerationSoftware/pt-v5-vault-boost), but both of those methods require the boost to be paid to the prize pool as POOL tokens. By using this prize hook as an incentives program, depositors can opt-in to a prize boost paid directly to them as any token.
