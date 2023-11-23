# Custom Sponsored Vault

| [Overview](#overview)
| [Design](#design)
| [Implementation](#implementation)
|

## Overview

In PoolTogether V5, anyone can create a custom vault that contributes prize tokens to the prize pool to earn depositors or stakeholders a chance to win prizes. In this example, we'll demonstrate the basics of a custom vault by creating a contract that allows users to deposit an ERC20 token and allows anyone to sponsor the vault by contributing prize tokens. Depositors will then have a chance to win prizes while they are deposited and can withdraw at any time.

## Design

There are three key components to a vault:

1. 🧾 TWAB Controller
2. 🏆 Prize Pool
3. 🎁 Prize Claimer

These components work together to award prizes everyday to winners in the vault.

### 🧾 TWAB Controller

The TWAB (Time-Weighted Average Balance) Controller is a contract that keeps track of user balances and is used by the prize pool to lookup an account's average balance over any period of time.

> Each deployment of PoolTogether V5 has a `TwabController` contract that keeps track of all vault balances. You can find the live deployments in the [developer documentation](https://dev.pooltogether.com/protocol/deployments/mainnet).

Our custom vault will be using three functions on the `TwabController`:

#### `TwabController.mint`

```solidity
function mint(address _to, uint96 _amount) external
```

We will call this function from the vault contract to mint share tokens when deposits are made.

> Note that the `mint` function takes a `uint96` value instead of a `uint256`. Storing historic balances is expensive to do onchain, so this optimization saves storage space and makes it cheaper to interact with the `TwabController`. However, some tokens have balances that can exceed this amount. If you are making a vault with one of these tokens, the vault will have to reduce the precision of the token when deposits are converted to vault shares.

#### `TwabController.burn`

```solidity
function burn(address _from, uint96 _amount) external
```

Our vault will call the `burn` function when a withdrawal occurs to reduce the internal share balance for the account.

#### `TwabController.balanceOf`

```solidity
function balanceOf(address vault, address user) external view returns (uint256)
```

Since our vault will store all internal balances in the `TwabController`, we will also need to use the `balanceOf` function to read balances for an account.

### 🏆 Prize Pool

The prize pool is the core contract for PoolTogether V5 that keeps track of vault contributions and awards prizes to winners using daily RNG. Our custom vault will need a function that allows anyone to sponsor prizes for the vault by contributing tokens to the prize pool.

> There is one `PrizePool` contract for each chain that PoolTogether V5 is deployed on. You can find the live deployments in the [developer documentation](https://dev.pooltogether.com/protocol/deployments/mainnet).
>
> The `PrizePool` contract also contains an immutable pointer to the `TwabController` contract that it uses: `PrizePool.twabController()`.

Standard vaults accrue yield through an underlying vault and then automatically auction the yield every day to liquidator bots that contribute the prize tokens to the prize pool on behalf of the vault. Since this example doesn't have any yield source, we will simplify this by having a function that allows anyone to donate prize tokens on behalf of the vault. The sponsor of the vault can then call this daily to give the depositors a chance to win the pooled prizes.

The function will have the following interface:

```solidity
function donatePrizeTokens(uint256 amount) external
```

The function will then transfer the amount of prize tokens to the prize pool and then call the following prize pool function:

```solidity
function contributePrizeTokens(address _prizeVault, uint256 _amount) external returns (uint256)
```

### 🎁 Prize Claimer

One of the new protocol features with V5 is automatic prize claims on behalf of users. This feature is implemented at the vault level, so we'll need to deploy a prize claimer contract that runs a daily auction for bots to compete in claiming prizes for winners. We can deploy a default claimer through the `ClaimerFactory` contract (live deployments can be found [here](https://dev.pooltogether.com/protocol/deployments/mainnet)).

#### Deploying a Claimer

We can deploy a claimer by calling the following function on the `ClaimerFactory` with the parameters listed below:

```solidity
function createClaimer(
  contract PrizePool _prizePool,
  uint256 _minimumFee,
  uint256 _maximumFee,
  uint256 _timeToReachMaxFee,
  UD2x18 _maxFeePortionOfPrize
) external returns (contract Claimer)
```

```solidity
PrizePool prizePool = 0xabc123; // Replace with the prize pool address for the chain you're deploying on
uint256 minimumFee = 1e14; // This is some small non-zero number that the claim fee will start at (denominated in prize tokens)
uint256 maximumFee = 1e22; // This is a number larger than the minimum that the claim fee will ramp up to over time
uint256 timeToReachMaxFee = 21600; // The time in seconds to reach the max fee
UD2x18 maxFeePortionOfPrize = 1e17; // (10%) The max fee as a portion of the prize being claimed
```

Our custom vault contract will extend the [`IClaimable` interface](https://github.com/GenerationSoftware/pt-v5-claimable-interface/blob/main/src/interfaces/IClaimable.sol) to provide an interface for the `Claimer` contract to interact with.

#### Claiming Prizes

Prizes are claimed by an open network of bots that compete with each other to claim prizes at the lowest rates. Most bots are configured to claim prizes for vaults created through the standard vault factory, but they may not automatically start claiming prizes from our custom vault since it is not discoverable in the same way.

To solve this, we will either need to petition known bot managers to start claiming prizes for our bot, or we can [create and run our own bot to claim prizes](https://dev.pooltogether.com/protocol/guides/claiming-prizes) on behalf of users.

## Implementation

### Constructor

#### Initialize the vault with a deposit asset, prize pool, and claimer address:

```solidity
error AssetZeroAddress();
error PrizePoolZeroAddress();
error ClaimerZeroAddress();

contract SponsoredVault is IClaimable {
  PrizePool public immutable prizePool;
  TwabController public immutable twabController;
  IERC20 public immutable asset;
  address public immutable claimer;

  constructor(IERC20 _asset, PrizePool _prizePool, address _claimer) {
    if (address(0) == address(_asset)) revert AssetZeroAddress();
    if (address(0) == address(_prizePool)) revert PrizePoolZeroAddress();
    if (address(0) == _claimer) revert ClaimerZeroAddress();
    prizePool = _prizePool;
    twabController = _prizePool.twabController();
    asset = _asset;
    claimer = _claimer;
  }
}
```

> Note that we get the `TwabController` from the prize pool since it MUST be the same for the vault to work.

###
