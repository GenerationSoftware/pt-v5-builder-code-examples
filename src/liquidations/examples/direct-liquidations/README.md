# Direct Liquidations

| [Overview](#overview)
| [Examples](#examples)
|

## Overview

Each vault has a `TpdaLiquidationPair` contract that acts as a one-way swap where the caller provides prize tokens and receives yield from the vault in return. This yield is continually auctioned in a [Target Period Dutch Auction (TPDA)](https://github.com/GenerationSoftware/pt-v5-tpda-liquidator/?tab=readme-ov-file#target-period-dutch-auction-liquidation-pair) and a swap can be initiated by anyone.

Each auction slowly drops the purchase price of the current available yield over time until it becomes profitable for someone to trigger the swap. As a result, to find the best swap available, one must consider gas price, yield price, prize token price, and the timing of their liquidation.

## Examples

To see how much yield is currently being auctioned, you can use the `maxAmountOut()` function. You can then call `computeExactAmountIn(uint256 amountOut)` on the liquidation pair to see the current asking price (in prize tokens) of the current yield.

> There is no benefit to swapping less than the `maxAmountOut` for a TPDA liquidation pair since the auction will not lower the price when liquidating less than the max amount out.

Once you find a profitable swap and verify that you will receive more profit in yield than you will spend in gas, you can initiate the swap with the `swapExactAmountOut` function:

```solidity
function swapExactAmountOut(
    address _receiver,
    uint256 _amountOut,
    uint256 _amountInMax,
    bytes memory _flashSwapData
) external returns (uint256)
```

The `TpdaLiquidationPair` contract expects the computed `amountIn` to be transferred to the `target` contract (the prize pool) before the swap is initialized. This means that we must create a helper function that atomically executes these actions in the same transaction.

> Unless you are creating a custom swap implementation, it is best to use the `TpdaLiquidationRouter` contract to perform liquidations on a `TpdaLiquidationPair`. The router provides atomic execution and extra user protections. Check out the guide on [how to use the liquidation router](../router-liquidations/README.md)!

After sending the required tokens to the `target` contract, you can call `swapExactAmountOut` with your address as the `_receiver`, the max amount out as the `_amountOut` and the exact `_amountInMax` based on the amount in (in prize tokens) that you calculated before. The `_flashSwapData` is optional and should only be used if you are performing a flashswap. You can read more on how to use flashswaps [here](../flash-swap-liquidations/README.md).
