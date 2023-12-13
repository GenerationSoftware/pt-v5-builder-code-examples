# Direct Liquidations

| [Overview](#overview)
| [Examples](#examples)
|

## Overview

Each vault has a `LiquidationPair` contract that acts as a one-way swap where the caller provides prize tokens (POOL) and receives yield from the vault in return. This yield is auctioned daily in a [continuous gradual dutch auction](https://github.com/GenerationSoftware/pt-v5-cgda-liquidator/blob/main/src/libraries/ContinuousGDA.sol) and a swap can be initiated by anyone.

Each daily auction has an amount of tokens to liquidate and adjusts the price based on the rate they are being liquidated. This means that if you try to swap for all the available yield at any given time, you will receive the worst available swap rate. Likewise, if you swap for the minimum amount of yield, you will receive the best available rate at that moment.

As a result, to find the best swap available, one must consider gas price, yield price, prize token price, and the timing of their liquidation.

## Examples

A simple algorithm to estimate the best swap rate is the following:

1. interpolate from `0` to `maxAmountOut` at a defined granularity:
   1. `computeExactAmountIn` for the given amount out
   2. convert the amount in to yield tokens based on your current available market rate
   3. take the difference of the `amountOut` and the `amountIn` in yield tokens
   4. if the difference is better than the current most profitable swap, then record it as the new most profitable swap

Once you find the most profitable swap for the `LiquidationPair` and verify that you will receive more profit in yield than you will spend in gas, you can initiate the swap with the `swapExactAmountOut` function:

```solidity
function swapExactAmountOut(
    address _receiver,
    uint256 _amountOut,
    uint256 _amountInMax,
    bytes memory _flashSwapData
) external returns (uint256)
```

The `LiquidationPair` contract expects the computed `amountIn` to be transferred to the `target` contract (the prize pool) before the swap is initialized. This means that we must create a helper function that atomically executes these actions in the same transaction.

> Unless you are creating a custom swap implementation, it is best to use the `LiquidationRouter` contract to perform liquidations on a `LiquidationPair`. The router provides atomic execution and extra user protections. Check out the guide on [how to use the liquidation router](../router-liquidations/README.md)!

After sending the required tokens to the `target` contract, you can call `swapExactAmountOut` with your address as the `_receiver`, the best amount out you found before as the `_amountOut` and the exact `_amountInMax` based on the amount in (in prize tokens) that you calculated before. The `_flashSwapData` is optional and should only be used if you are performing a flashswap. You can read more on how to use flashswaps [here](../flash-swap-liquidations/README.md).
