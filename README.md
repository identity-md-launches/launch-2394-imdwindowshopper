# IMDwindowshopper (WWW)

> Stop window shopping. See everything first. — @windowshoppermd

A fixed-supply ERC-20 token, built as an IMD custom-token launch on Ethereum (chain id 1).

| Property | Value |
| --- | --- |
| Solidity contract | `WindowShopperToken` (`src/WindowShopperToken.sol`) |
| `name()` | `IMDwindowshopper` |
| `symbol()` | `WWW` |
| `decimals()` | `18` |
| `totalSupply()` | `1000000000000000000000000000` (1,000,000,000 × 10^18), fixed |
| Constructor arguments | none |

## Behaviour

- The constructor mints the whole supply **once** to `msg.sender` (the deployer). On launch that
  is the IMD factory, which distributes it.
- It is a standard OpenZeppelin v5.1.0 `ERC20`. Transfers move exactly the amount they name:
  there is no fee, tax, burn, reflection, cooldown or transfer limit.
- There is **no owner and no admin**: no mint, pause, blacklist, freeze, seize or `burnFrom`,
  and no upgrade path. Nobody can increase the supply after deployment, and nobody but a holder
  (or a spender the holder approved) can move a holder's balance.
- The contract does not accept ETH and makes no external calls. Its runtime code contains no
  `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`.
- Standard OpenZeppelin errors: `ERC20InsufficientBalance`, `ERC20InsufficientAllowance`,
  `ERC20InvalidReceiver` (transfer to the zero address), `ERC20InvalidSpender` (approve the zero
  address). An allowance of `type(uint256).max` is treated as infinite and is not decremented.

## Assumptions

- The brief asks for a plain token: name, symbol, 1,000,000,000 supply with 18 decimals, all
  minted to the deployer. "Stop window shopping. See everything first." is the project tagline,
  not an on-chain mechanism, so no extra behaviour was added.
- The usual ERC-20 `approve` front-running caveat applies (change an allowance to 0 before
  setting a new non-zero value, or use exact allowances).

## Deployment parameters

The launch (IMD's factory via `ProjectFactory.launchCustom`) deploys the token from its creation
code, with no constructor arguments, and does the distribution itself. These values are decided
by the launch and are recorded here for reference; the manifest step writes `launch.json`.

- Chain: Ethereum mainnet (1).
- Token: `WindowShopperToken`, decimals 18, total supply `1000000000000000000000000000`.
- Pool: paired with IMD (`0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`), fee `12500` (1.25%),
  tick spacing `60`. The opening price is derived by IMD's deployer from the economics below.
- Economics (requester's): `poolBps` 5000 (50% of supply seeds the pool), `initialMarketCapWei`
  `900000000000000000000` (900 IMD for the whole supply), remainder (40%) to
  `0xee2aaa315cf7ed169f93148d30d24af9318dbb66`. The remaining 10% goes to the swarm's
  MerkleDistributor, sent by the factory.

No owner-settable values exist, so there is no "After launch" configuration.

## Operational responsibilities

- Nothing to operate: the token has no admin functions and needs no keeper, oracle or setter.
- Deployment, explorer source verification and pool creation are performed by IMD's launch
  deployer, not by this repository. No script here broadcasts transactions or holds keys.
- Passing tests are not an audit. The contract is a minimal wrapper around audited OpenZeppelin
  code, but an independent review before launch is still recommended.

## Build and test

```sh
forge build
forge test
forge fmt --check
```

Compiler `solc 0.8.26` (pinned in `foundry.toml`, `bytecode_hash = "none"`, optimizer 200 runs,
EVM `cancun`). Dependencies are vendored as plain files under `lib/`:

| Library | Version / commit | Use |
| --- | --- | --- |
| OpenZeppelin Contracts | v5.1.0 (`69c8def5`) | `ERC20` |
| forge-std | v1.9.7 (`77041d2c`) | tests |
| Uniswap v4-core | `46c68346` (src only) | launch-flow checks |
| solmate | `4b47a190` (src only) | v4-core dependency |

Tests in `test/WindowShopperToken.t.sol` cover metadata, the single mint to the deployer, the
absence of mint/admin entry points, transfers and allowances (success and every failure path),
and fuzzed supply conservation and allowance accounting.
