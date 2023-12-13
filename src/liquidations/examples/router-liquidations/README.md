# Router Liquidations

| [Overview](#overview)
| [Examples](#examples)
| [Flash Swaps](#flash-swaps)
|

## Overview

The `LiquidationRouter` is a helper contract that enforces configurable protections on swaps made through `LiquidationPair` contracts deployed through the factory. If a liquidation does not require any special functionality, then it is recommended to use the `LiquidationRouter` instead of interacting directly with the `LiquidationPair`. The router also provides the benefit of only needing to approve prize token spending on one contract rather than each individual pair.

## Examples

The `LiquidationRouter` has a function called `swapExactAmountOut`:

```solidity
function swapExactAmountOut(
    contract LiquidationPair _liquidationPair,
    address _receiver,
    uint256 _amountOut,
    uint256 _amountInMax,
    uint256 _deadline
) external returns (uint256)
```

As the name suggests, this function takes an `_amountOut` parameter (denoted in vault tokens for the specific `LiquidationPair`) that the `_receiver` must receive in a successful execution as well as an `_amountInMax` parameter that limits the amount of prize tokens that can be payed for the swap. Additionally, there is a `_deadline` parameter that acts as a failsafe incase the transaction is not included in a block by the specified timestamp.

### Swap 10 POOL for 8 pUSDC.e:

```solidity
swapExactAmountOut(
    LiquidationPair(0xe7680701a2794E6E0a38aC72630c535B9720dA5b), // LP for pUSDC.e on Optimism
    address(msg.sender), // replace with your receiver address,
    10e18, // 10 POOL
    8e6, // 8 pUSDC.e
    1700939873 // deadline (replace with current timestamp + max inclusion time)
);
```

If the liquidation is successful, the following event will be emitted:

```solidity
event SwappedExactAmountOut(
    LiquidationPair indexed liquidationPair,
    address indexed sender,
    address indexed receiver,
    uint256 amountOut,
    uint256 amountInMax,
    uint256 amountIn,
    uint256 deadline
);
```

### Common Errors

#### `UnknownLiquidationPair`

Thrown if the `LiquidationPair` was not deployed by the factory contract.

#### `SwapExpired`

Thrown if the deadline has expired.

## Flash Swaps

The `LiquidationPair` contract supports flash swaps through a callback that is triggered after the prize tokens are transferred to the receiver. Flashswaps are _not_ possible through the `LiquidationRouter` and require a special implementation to function.

For an example on executing a flash swap through a specific pair, see the [flash swap example](../flash-swap-liquidations/README.md).
