# PoolTogether V5 Builder Code Examples

A collection of code examples for builders looking to build with the PoolTogether V5 protocol.

## Directory

### Vault Prize Hook Examples

- [Awarding Prizes to NFT Holders](./src/prize-hooks/examples/prize-to-nft-holder/README.md)
- [Minting Tokens to Prize Winners](./src/prize-hooks/examples/prize-pixels/README.md)
- [Redirecting Prizes to a Different Address](./src/prize-hooks/examples/prize-burn/README.md)
- [Donating Prizes back to the Prize Pool](./src/prize-hooks/examples/prize-recycle/README.md)

> For more info on prize hooks, see the [prize hook reference docs](https://dev.pooltogether.com/).

## Repository - Development & Testing

### Installation

You may have to install the following tools to use this repository:

- [Foundry](https://github.com/foundry-rs/foundry) to compile and test contracts
- [direnv](https://direnv.net/) to handle environment variables
- [lcov](https://github.com/linux-test-project/lcov) to generate the code coverage report

Install dependencies:

```
npm i
```

### Env

Copy `.envrc.example` and write down the env variables needed to run this project.

```
cp .envrc.example .envrc
```

Once your env variables are setup, load them with:

```
direnv allow
```

### Compile

Run the following command to compile the contracts:

```
npm run compile
```

### Coverage

Forge is used for coverage, run it with:

```
npm run coverage
```

You can then consult the report by opening `coverage/index.html`:

```
open coverage/index.html
```

### Code quality

[Husky](https://typicode.github.io/husky/#/) is used to run [lint-staged](https://github.com/okonet/lint-staged) and tests when committing.

[Prettier](https://prettier.io) is used to format TypeScript and Solidity code. Use it by running:

```
npm run format
```

[Solhint](https://protofire.github.io/solhint/) is used to lint Solidity files. Run it with:

```
npm run hint
```

### CI

A default Github Actions workflow is setup to execute on push and pull request.

It will build the contracts and run the test coverage.

You can modify it here: [.github/workflows/coverage.yml](.github/workflows/coverage.yml)

For the coverage to work, you will need to setup the `MAINNET_RPC_URL` repository secret in the settings of your Github repository.
