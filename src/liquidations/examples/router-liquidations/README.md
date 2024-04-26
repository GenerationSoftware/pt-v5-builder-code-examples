# Router Liquidations

| [Overview](#overview)
| [Examples](#examples)
| [Flash Swaps](#flash-swaps)
|

## Overview

The `TpdaLiquidationRouter` is a helper contract that enforces configurable protections on swaps made through `TpdaLiquidationPair` contracts deployed through the factory. If a liquidation does not require any special functionality, then it is recommended to use the router instead of interacting directly with the `TpdaLiquidationPair`. The router also provides the benefit of only needing to approve prize token spending on one contract rather than each individual pair.

## Examples

The `TpdaLiquidationRouter` has a function called `swapExactAmountOut`:

```solidity
function swapExactAmountOut(
    contract TpdaLiquidationPair _liquidationPair,
    address _receiver,
    uint256 _amountOut,
    uint256 _amountInMax,
    uint256 _deadline
) external returns (uint256)
```

As the name suggests, this function takes an `_amountOut` parameter (denoted in vault tokens for the specific `TpdaLiquidationPair`) that the `_receiver` will receive in a successful execution as well as an `_amountInMax` parameter that limits the amount of prize tokens that can be payed for the swap. If this limit is exceeded, the transaction will revert. Additionally, there is a `_deadline` parameter that acts as a failsafe incase the transaction is not included in a block by the specified timestamp.

### Swap 0.001 WETH for 4 przUSDC:

```solidity
swapExactAmountOut(
    TpdaLiquidationPair(0x7d72e1043FBaCF54aDc0610EA8649b23055462f0), // LP for przUSDC on Optimism
    address(msg.sender), // replace with your receiver address,
    0.001e18, // 0.001 WETH
    4e6, // 4 przUSDC
    1714144434 // deadline (replace with current timestamp + max inclusion time)
);
```

If the liquidation is successful, the following event will be emitted:

```solidity
event SwappedExactAmountOut(
    TpdaLiquidationPair indexed liquidationPair,
    address indexed sender,
    address indexed receiver,
    uint256 amountOut,
    uint256 amountInMax,
    uint256 amountIn,
    uint256 deadline
);
```

## Flash Swaps

The `TpdaLiquidationPair` contract supports flash swaps through a callback that is triggered after the prize tokens are transferred to the receiver. Flashswaps are _not_ possible through the `TpdaLiquidationRouter` and require a special implementation to function.

For an example on executing a flash swap through a specific pair, see the [flash swap example](../flash-swap-liquidations/README.md).
