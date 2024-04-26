# Custom Sponsored Vault

| [Overview](#overview)
| [Design](#design)
| [Implementation](#implementation)
| [Standardization](#standardization)
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

> Each deployment of PoolTogether V5 has a `TwabController` contract that keeps track of all vault balances. You can find the live deployments in the [developer documentation](https://dev.pooltogether.com/protocol/deployments/).

Our custom vault will be using Generation Software's [`TwabERC20`](https://github.com/GenerationSoftware/pt-v5-vault/blob/a10aaa1d1a04e19253a8a7c64aa384e2cb67fb2e/src/TwabERC20.sol) helper contract to automatically manage TWAB shares while only having to call the `_mint` and `_burn` functions.

### 🏆 Prize Pool

The prize pool is the core contract for PoolTogether V5 that keeps track of vault contributions and awards prizes to winners using daily RNG. Our custom vault will need a function that allows anyone to sponsor prizes for the vault by contributing tokens to the prize pool.

> There is one `PrizePool` contract for each chain that PoolTogether V5 is deployed on. You can find the live deployments in the [developer documentation](https://dev.pooltogether.com/protocol/deployments/).
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

One of the new protocol features with V5 is automatic prize claims on behalf of users. This feature is implemented at the vault level, so we'll need to use a prize claimer contract that runs a daily auction for bots to compete in claiming prizes for winners. We can deploy a our own claimer contract through the `ClaimerFactory` (live deployments can be found [here](https://dev.pooltogether.com/protocol/deployments/)) or we can use an existing claimer if the parameters match the needs for our vault.

#### Making it Claimable

To work with the claimer contract, our custom vault will need to implement the [`IClaimable`](https://github.com/GenerationSoftware/pt-v5-claimable-interface/blob/ee0c50aaef23407402f7dc0378a81b4eb1385c5a/src/interfaces/IClaimable.sol) interface. The easiest way to do that is by extending Generation Software's [`Claimable`](https://github.com/GenerationSoftware/pt-v5-vault/blob/main/src/abstract/Claimable.sol) contract, which sets up all the needed functions for claims to occur and even lets depositors add auto-executing prize hooks to their wins.

#### Claiming Prizes

Prizes are claimed by an open network of bots that compete with each other to claim prizes at the lowest rates. Most bots are configured to claim prizes for vaults created through the standard vault factory, but they may not automatically start claiming prizes from our custom vault since it is not discoverable in the same way.

To solve this, we will either need to petition known bot managers to start claiming prizes for our vault, or we can [create and run our own bot to claim prizes](https://dev.pooltogether.com/protocol/guides/claiming-prizes) on behalf of users.

## Implementation

### Constructor

#### Initialize the vault by extending the `TwabERC20` and `Claimable` contracts and initialize the deposit asset:

```solidity
error AssetZeroAddress();

contract SponsoredVault is TwabERC20, Claimable {
  IERC20 public immutable asset;

  constructor(
    string memory _name,
    string memory _symbol,
    IERC20 _asset,
    PrizePool _prizePool,
    address _claimer
  ) TwabERC20(_name, _symbol, _prizePool.twabController()) Claimable(_prizePool, _claimer) {
    if (address(0) == address(_asset)) revert AssetZeroAddress();
    asset = _asset;
  }
}
```

> Note that we get the `TwabController` from the prize pool since it MUST be the same for the vault to work.

### Deposits

#### Add a function to deposit assets:

```solidity
function deposit(uint256 _amount) external {
  asset.safeTransferFrom(msg.sender, address(this), _amount);
  _mint(msg.sender, _amount);
}
```

All accounting logic is handled by `TwabERC20`, so we call the `_mint` function to increase the depositor's vault shares.

> Note that we do the state change _after_ the assets have been transferred to the contract. This prevents reentrancy attacks from inflating their share value past their deposited asset value.

### Withdrawals

#### Add a function to withdraw assets:

```solidity
function withdraw(uint256 _amount) external {
  _burn(msg.sender, _amount);
  asset.safeTransfer(msg.sender, _amount);
}
```

Similar to the deposit function, we handle the accounting changes through the `TwabERC20` extension. We are withdrawing assets, so we use the `_burn` function to decrease the shares that the depositor holds.

> Note that we `burn` shares _before_ transferring any assets to prevent reentrancy attacks from being able to inflate their asset balance past their share value.

### Sponsoring the Vault

#### Add a function to donate prize tokens to the prize pool on behalf of the vault:

```solidity
function donatePrizeTokens(uint256 _amount) external {
  prizePool.prizeToken().safeTransferFrom(
    msg.sender,
    address(prizePool),
    _amount
  );
  prizePool.contributePrizeTokens(address(this), _amount);
}
```

The caller must approve this contract to spend their prize tokens before calling this function. Once called, the prize tokens will be transferred to the prize pool and contributed on behalf of this vault, giving the depositors to the vault a chance to win prizes.

### Done!

See the full implementation [here](./SponsoredVault.sol).

## Standardization

To keep this example as simple as possible, the vault contract has not been adapted to any vault standards; however, if we want the depositors to get the most utility out of the vault, it should implement the [ERC4626 vault standard](https://ethereum.org/en/developers/docs/standards/tokens/erc-4626/). This would enable our vault to be compatible with many 3rd party services that provide additional utility. The vault would also be viewable through interfaces like [Cabana](https://app.cabana.fi/) if we create a [vault list](https://docs.cabana.fi/cabana-app/vault-lists) with our custom vault.
