# Flash Swap Liquidations

| [Overview](#overview)
| [Design](#deisgn)
| [Example](#example)
| [Try it out](#try-it-out)
|

## Overview

Flashswaps are unique swaps where the sender receives the output first, executes some external logic to obtain input tokens and sends the required input amount to the swap contract, keeping the profit from the arbitrage. In order for this to be possible, the contract verifies that the required token input has been received at the end of the transaction and fails if they haven't.

In PoolTogether V5, flashswaps can be used with yield liquidations as a way to atomically liquidate yield for prize tokens with an onchain market without having to worry about volatility.

The `ILiquidationPair` contract natively implements flashswap functionality by allowing the caller to provide some additional data that is used to trigger a custom flashswap callback.

## Design

The `ILiquidationPair` contract has an optional parameter `bytes memory _flashSwapData` that can be passed to the `swapExactAmountOut` function to initiate a flashswap. If provided, the [`flashSwapCallback`](https://github.com/GenerationSoftware/pt-v5-liquidator-interfaces/blob/b934e0ae66eeb2e2feb978e5edd2bd0b8b1eacf6/src/interfaces/IFlashSwapCallback.sol) function will be called on the receiver contract after it has been sent the yield from the swap. The callback function is also passed the additional flashswap data that was provided. This data can hold any information and should be used as extra arguments for the flashswap implementation.

During the callback function, the flashswap contract must acquire the necessary prize tokens and send them back to the `ILiquidationPair`'s target contract. Any additional tokens acquired past the amount due can be treated as profit.

## Example

For an example of using a `ILiquidationPair` flashswap with Uniswap, see this [example flashswap contract](https://github.com/GenerationSoftware/pt-v5-flash-liquidator/blob/main/src/UniswapFlashLiquidation.sol).
