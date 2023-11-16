# Hook to Award Prizes to a Random NFT Holder

| [Overview](#overview)
| [Design](#design)
| [Implementation](#implementation)
| [Setting the Hook](#setting-the-hook)
|

## Overview

In this example we will demonstrate how to award prizes to random holders of an NFT using a prize hook. This can be used for NFT promotions or to integrate prize savings directly with tokenized collectibles.

## Design

The core principle of awarding prizes to a random NFT holder is simple: we use the entropy from the daily draw to select a random NFT holder and redirect the prize to them using the `beforePrizeClaim` hook. To accomplish this we need to ensure two things:

1. The entropy can not be manipulated by NFT holders.
2. The NFT holders are enumerable (we know how many there are and can get the owner's address of the `nth` token)

## Implementation

#### Set up the hook contract and extend the `IVaultHooks` interface:

```solidity
import { IVaultHooks } from "pt-v5-vault/interfaces/IVaultHooks.sol";

contract PrizeToEnumerableNFTHolderHook is IVaultHooks {
  // hook code goes here...
}
```

#### Create a constructor that sets the enumerable token address and prize pool address:

```solidity
import { IERC721Enumerable } from "openzeppelin/token/ERC721/extensions/IERC721Enumerable.sol";
import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";

error TokenNotERC721Enumerable();
error PrizePoolAddressZero();

contract PrizeToEnumerableNFTHolderHook is IVaultHooks {
  IERC721Enumerable public enumerableToken;
  PrizePool public prizePool;

  constructor(IERC721Enumerable enumerableToken_, PrizePool prizePool_) {
    if (address(0) == address(prizePool_)) {
      revert PrizePoolAddressZero();
    }
    if (
      !enumerableToken_.supportsInterface(type(IERC721Enumerable).interfaceId)
    ) {
      revert TokenNotERC721Enumerable();
    }

    enumerableToken = enumerableToken_;
    prizePool = prizePool_;
  }
}
```

> Note that we check to ensure that the NFT implements the OpenZeppelin `IERC721Enumerable` interface to ensure that the token contract provides the functions needed to pick a random token holder.

#### Implement the `beforeClaimPrize` hook and use the random number from the awarded draw as entropy to select a random NFT holder:

```solidity
import { UniformRandomNumber } from "uniform-random-number/UniformRandomNumber.sol";

// ...

function beforeClaimPrize(
  address,
  uint8 tier,
  uint32 prizeIndex,
  uint96,
  address
) external view returns (address) {
  uint256 _entropy = uint256(
    keccak256(abi.encode(prizePool.getWinningRandomNumber(), tier, prizeIndex))
  );
  uint256 _randomTokenIndex = UniformRandomNumber.uniform(
    _entropy,
    enumerableToken.totalSupply()
  );
  return
    enumerableToken.ownerOf(enumerableToken.tokenByIndex(_randomTokenIndex));
}
```

> Note that we include the tier and prize index in the entropy so that each individual prize won in a draw can have a different winner.

> We also use the `UniformRandomNumber` library to ensure we don't introduce any [modulo bias](https://medium.com/hownetworks/dont-waste-cycles-with-modulo-bias-35b6fdafcf94) to the random selection.

#### Add an empty `afterClaimPrize` hook to satisfy the `IVaultHooks` interface:

```solidity
function afterClaimPrize(
  address,
  uint8,
  uint32,
  uint256,
  address
) external pure {}
```

### Done!

We now have a hook that can award prizes to random NFT holders! See the full implementation [here](./PrizeToNFTHolderHook.sol).

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
