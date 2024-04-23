# Prize Pixels - Vault Hook

### _Using Hooks to Mint Additional Tokens To Winners_

| [Overview](#overview)
| [Design](#design)
| [Implementation](#implementation)
| [Setting the Hook](#setting-the-hook)
|

## Overview

In this example, we'll use prize hooks to mint additional tokens (Prize Pixels) to winners in PoolTogether V5. These tokens could then be redeemed and used to paint on a communal canvas to provide a fun and interactive experience through prize hooks; however, in this example we will just demonstrate token minting process.

## Design

In this example, we'll assume that our end product will use a communal canvas of a predefined pixel width and height. Therefore, we should ensure that our prize pixels are minted at a defined daily rate such that the number of pixels that can be used to paint on the canvas each day is stable even if the number of daily winners varies drastically over time.

### Stable Daily Mint Rate

We can achieve a simple stable mint rate of `x` per day by only minting prize pixels to winners of the first `x` daily prizes. If the number of estimated prizes in the daily tier (`n`) is less than `x`, then each winner will receive a proportional amount of the daily mint rate (`x` / `n`), otherwise each winner will receive exactly one prize pixel.

### Verifying Winners

Since the hook should support all vaults, not just vaults deployed by the current vault factory, we need a reliable way to verify that a winner has won a prize before minting them prize pixels.

The prize pool contract provides an `isWinner` function that can be used to verify if the given address has won a specific prize on a vault for the last awarded draw. We can call this function with the data passed to the `afterPrizeClaim` hook to verify a winner before we mint them prize tokens.

To protect against replay attacks from malicious vaults, we will also maintain a mapping of hooked prizes to ensure it's impossible to win prize pixels more than once for the same prize.

## Implementation

#### Import the `IPrizeHooks` interface and extend the contract with OpenZeppelin's ERC20 base contract:

```solidity
import { ERC20 } from "openzeppelin-v5/token/ERC20/ERC20.sol";
import { IPrizeHooks } from "pt-v5-vault/interfaces/IPrizeHooks.sol";

contract PrizePixelHook is ERC20, IPrizeHooks {
  // hook code goes here...
}
```

#### Add a constructor to initialize the contract with the prize pool address and target daily mint rate:

```solidity
import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";

// ...

error TargetMintPerDayZero();
error PrizePoolAddressZero();

uint256 public targetMintPerDay;
PrizePool public prizePool;

constructor(uint256 targetMintPerDay_, PrizePool prizePool_) ERC20("Prize Pixel", "PrizePixel") {
  if (0 == targetMintPerDay_) revert TargetMintPerDayZero();
  if (address(0) == address(prizePool_)) revert PrizePoolAddressZero();

  targetMintPerDay = targetMintPerDay_;
  prizePool = prizePool_;
}
```

#### Add the required hooks for the `IPrizeHooks` interface:

```solidity
function beforeClaimPrize(
  address,
  uint8,
  uint32,
  uint96,
  address
) external pure returns (address, bytes memory) {
  // We won't need this hook, so it can remain empty.
}

function afterClaimPrize(
  address winner,
  uint8 tier,
  uint32 prizeIndex,
  uint256, // We won't need the prize value in our calculations
  address recipient,
  bytes memory
) external {
  /// Prize pixel minting logic goes here...
}
```

#### Check if the winner is eligible for prize pixels:

```solidity
function afterClaimPrize(...) external {
  if (tier == prizePool.numberOfTiers() - 3 && prizeIndex < targetMintPerDay) {

    // ...

  }
}
```

#### Verify that the proclaimed winner has actually won a prize:

```solidity
error DidNotWin(address vault, address winner, uint8 tier, uint32 prizeIndex);
```

```solidity
if (!prizePool.isWinner(msg.sender, winner, tier, prizeIndex)) {
  revert DidNotWin(msg.sender, winner, tier, prizeIndex);
}
```

> Note that we use the message sender as the vault address since hooks are called from vault contracts.

#### Protect against replay attacks:

```solidity
error RepeatPrizeHook(
  address vault,
  address winner,
  uint24 drawId,
  uint8 tier,
  uint32 prizeIndex
);
```

```solidity
mapping(address vault =>
  mapping(address account =>
    mapping(uint24 drawId =>
      mapping(uint8 tier =>
        mapping(uint32 prizeIndex => bool hooked)
      )
    )
  )
) internal _hookedPrizes;
```

```solidity
uint24 _awardedDrawId = prizePool.getLastAwardedDrawId();
if (_hookedPrizes[msg.sender][winner][_awardedDrawId][tier][prizeIndex]) {
  revert RepeatPrizeHook(msg.sender, winner, _awardedDrawId, tier, prizeIndex);
}
_hookedPrizes[msg.sender][winner][_awardedDrawId][tier][prizeIndex] = true;
```

#### Mint the winner a proportional amount of prize pixels based on the estimated number of winners:

```solidity
event WonPrizePixels(
  address indexed recipient,
  uint256 tokensPerWinner,
  address indexed winner,
  uint8 indexed tier,
  uint32 prizeIndex
);
```

```solidity
uint32 _estimatedNumberOfPrizes = prizePool.getTierPrizeCount(tier);
uint256 tokensPerWinner = 1;
if (_estimatedNumberOfPrizes < targetMintPerDay) {
  tokensPerWinner = targetMintPerDay / _estimatedNumberOfPrizes;
}

emit WonPrizePixels(recipient, tokensPerWinner, winner, tier, prizeIndex);
_mint(recipient, tokensPerWinner);
```

We use the `getTierPrizeCount` function on the prize pool to estimate the number of daily prizes that were won in the last awarded draw. If there are less expected winners than the daily mint rate of prize pixels, then each winner will receive a proportional amount of the target mint rate.

### Done!

Now anybody who uses the hook has an additional chance to win prize pixels everyday! See the full implementation [here](./PrizePixelHook.sol).

## Setting the Hook

If a you want to set this hook on a prize vault, you will need to:

1. Deploy the hook contract, or use an existing deployment
2. Call `setHooks` on the prize vault contract with the following information:

```solidity
VaultHooks({
  useBeforeClaimPrize: false;
  useAfterClaimPrize: true;
  implementation: 0x... // replace with the hook deployment contract
});
```
