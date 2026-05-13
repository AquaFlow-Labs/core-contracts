# org/core-contracts

> The heart of the protocol. `CoreProtocol` is the primary on-chain entry point for funding — it receives ERC-20 tokens and automatically routes them to three sub-projects using [Drips V2](https://drips.network) splits.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [How Funds Flow](#how-funds-flow)
- [Drips V2 Integration](#drips-v2-integration)
- [Contract Reference](#contract-reference)
- [Interfaces](#interfaces)
- [Code Snippets](#code-snippets)
- [Deployment](#deployment)
- [Deployed Addresses](#deployed-addresses)
- [Testing](#testing)
- [Development](#development)
- [Tech Stack](#tech-stack)

---

## Overview

`CoreProtocol` is a Solidity smart contract that acts as the central funding hub for the protocol. It is built on top of [Drips V2](https://drips.network) — a decentralized, non-custodial ERC-20 streaming and splitting protocol on Ethereum.

When donors send tokens to `CoreProtocol`, those funds accumulate in the contract's Drips account. Anyone can then trigger `distributeYield(token)` to split the accumulated balance across three registered sub-projects according to pre-configured percentage weights. The splits configuration is set once at deployment and cannot be changed, making the funding distribution fully transparent and trustless.

Key properties:

- **Permissionless distribution** — `distributeYield` is callable by anyone; no admin key required.
- **Immutable splits** — weights are locked at construction time via `AddressDriver.setSplits()`.
- **Any ERC-20** — the contract works with any ERC-20 token; each token has an independent splittable balance.
- **Direct giving** — donors can bypass streaming and fund a specific sub-project instantly via `give()`.
- **Non-custodial collection** — leftover (non-split) funds can be swept to any address via `collect()`.

---

## Architecture

```
                        ┌─────────────────────────────┐
                        │        Funder / Donor        │
                        │   (EOA or external contract) │
                        └──────────────┬──────────────┘
                                       │
                          ┌────────────┴────────────┐
                          │  stream via Drips        │  give(receiverId, token, amt)
                          │  (per-second rate)       │  (one-time, immediate)
                          └────────────┬────────────┘
                                       │
                                       ▼
                        ┌─────────────────────────────┐
                        │         CoreProtocol         │
                        │    (AddressDriver account)   │
                        │                              │
                        │  addressDriver  ──► setSplits│ ◄── set once at deploy
                        │  drips          ──► split()  │ ◄── called by distributeYield()
                        │                              │
                        │  + distributeYield(token)    │
                        │  + collect(token, to)        │
                        │  + give(receiverId, token, amt)│
                        │  + accountId() view          │
                        │  + splitsReceivers() view    │
                        └──────────────┬──────────────┘
                                       │
                              drips.split() called
                                       │
                    ┌──────────────────┼──────────────────┐
                    ▼                  ▼                  ▼
             ┌───────────┐      ┌───────────┐      ┌───────────┐
             │ Sub-proj A│      │ Sub-proj B│      │ Sub-proj C│
             │  40%      │      │  30%      │      │  30%      │
             │ (400,000) │      │ (300,000) │      │ (300,000) │
             └───────────┘      └───────────┘      └───────────┘
```

### Component responsibilities

| Component         | Responsibility                                                                 |
|-------------------|--------------------------------------------------------------------------------|
| `CoreProtocol`    | Holds splits config, exposes `distributeYield`, `collect`, and `give`          |
| `AddressDriver`   | Drips V2 driver — manages this contract's account (setSplits, collect, give)   |
| `Drips`           | Drips V2 core — executes the split, tracks splittable balances per account     |
| Sub-projects A/B/C| Downstream Drips accounts that receive split funds                             |

---

## How Funds Flow

Funds move through three distinct stages:

### 1. Funding

Donors have two options:

**Stream** — set up a continuous per-second ERC-20 stream directly to `CoreProtocol`'s Drips account ID (returned by `accountId()`). Streams accumulate in the splittable balance over time and can be started, modified, or stopped at any point.

**Give** — call `give(receiverId, token, amt)` on `CoreProtocol` to make a one-time, immediate transfer to a specific sub-project. Tokens are pulled from the caller via `safeTransferFrom`, approved to `AddressDriver`, and forwarded in a single transaction.

### 2. Splitting

Anyone calls `distributeYield(token)`. Internally this calls `Drips.split()` with:
- the contract's own account ID (derived from its address)
- the ERC-20 token to split
- the stored `_splits` array (the immutable weights config)

The Drips core contract reads the splittable balance for that account + token, applies the weight fractions, and credits each sub-project's collectable balance accordingly. The entire splittable balance is consumed in one call.

Weight fractions are expressed out of `1,000,000`:

| Sub-project | Weight    | Percentage |
|-------------|-----------|------------|
| A           | 400,000   | 40%        |
| B           | 300,000   | 30%        |
| C           | 300,000   | 30%        |
| **Total**   | **1,000,000** | **100%** |

If weights sum to less than `1,000,000`, the remainder stays collectable by `CoreProtocol` itself and can be swept via `collect()`.

### 3. Collecting

`collect(token, to)` calls `AddressDriver.collect()` which transfers any collectable (non-split) balance held by this contract's Drips account to the specified `to` address. This is useful for recovering dust or any funds that weren't fully split.

---

## Drips V2 Integration

`CoreProtocol` is an **AddressDriver** account. In Drips V2, every Ethereum address automatically has a corresponding Drips account — no registration required. The account ID is deterministically derived from the address:

```solidity
uint256 accountId = addressDriver.calcAccountId(address(this));
```

The splits configuration is registered once in the constructor:

```solidity
addressDriver.setSplits(receivers);
```

After deployment, the splits are locked. Any attempt to call `setSplits` again would require calling it through `AddressDriver` directly (which `CoreProtocol` does not expose), so the distribution ratios are effectively immutable from the protocol's perspective.

### Drips V2 contract addresses

| Network          | Contract        | Address                                      |
|------------------|-----------------|----------------------------------------------|
| Ethereum Mainnet | `Drips`         | `0xd0Dd053392db676D57317CD4fe96Fc2cCf42D0b4` |
| Ethereum Mainnet | `AddressDriver` | `0x1455d9bD6B98f95dd8FEB2b3D60ed825fcef0610` |
| Sepolia Testnet  | `Drips`         | `0x74A32a38D945b9527524900429b083547DeB9bF4` |
| Sepolia Testnet  | `AddressDriver` | `0x70E1E1437AeFe8024B6780C94490662b45C3B567` |

Full details at [docs.drips.network/the-protocol/smart-contract-details](https://docs.drips.network/the-protocol/smart-contract-details).

---

## Contract Reference

### `CoreProtocol.sol`

#### State variables

| Variable        | Type                  | Visibility | Description                                      |
|-----------------|-----------------------|------------|--------------------------------------------------|
| `TOTAL_WEIGHT`  | `uint32`              | `public constant` | Maximum total weight — `1_000_000` (= 100%) |
| `addressDriver` | `IAddressDriver`      | `public immutable` | Drips V2 AddressDriver contract             |
| `drips`         | `IDrips`              | `public immutable` | Drips V2 core contract                      |
| `_splits`       | `SplitsReceiver[]`    | `private`  | Stored splits config used in every `split()` call |

#### Functions

| Function | Visibility | Description |
|---|---|---|
| `constructor(address, address, SplitsReceiver[])` | — | Sets `addressDriver`, `drips`, validates and stores receivers, calls `setSplits` |
| `distributeYield(IERC20 token)` | `external` | Calls `Drips.split()` to distribute splittable balance to sub-projects |
| `collect(IERC20 token, address to)` | `external` | Sweeps collectable (non-split) balance to `to` |
| `give(uint256 receiverId, IERC20 token, uint128 amt)` | `external` | Pulls tokens from caller and gives them directly to a sub-project |
| `accountId()` | `external view` | Returns this contract's Drips account ID |
| `splitsReceivers()` | `external view` | Returns the stored splits configuration array |

#### Constructor validation

The constructor enforces:
- The sum of all receiver weights must be `<= 1_000_000`.
- Receivers must be sorted ascending by `accountId` (enforced by the Drips protocol on-chain in `setSplits`).

---

## Interfaces

### `DripsStructs.sol`

```solidity
/// @notice A splits receiver entry. Weights must sum to <= 1_000_000.
struct SplitsReceiver {
    uint256 accountId; // Drips account ID of the receiver
    uint32  weight;    // Fraction of funds to receive, out of 1_000_000
}
```

### `IAddressDriver.sol`

```solidity
interface IAddressDriver {
    /// @notice Register or update the splits configuration for the caller's account.
    function setSplits(SplitsReceiver[] calldata receivers) external;

    /// @notice Immediately transfer `amt` of `erc20` to `receiverId`'s Drips account.
    function give(uint256 receiverId, IERC20 erc20, uint128 amt) external;

    /// @notice Collect all collectable funds for the caller's account and send to `transferTo`.
    function collect(IERC20 erc20, address transferTo) external returns (uint128 amt);

    /// @notice Compute the Drips account ID for a given Ethereum address.
    function calcAccountId(address userAddr) external view returns (uint256 accountId);
}
```

### `IDrips.sol`

```solidity
interface IDrips {
    /// @notice Split the splittable balance of `accountId` for `erc20` among its splits receivers.
    /// @param currReceivers Must match the receivers currently set for the account.
    function split(uint256 accountId, IERC20 erc20, SplitsReceiver[] calldata currReceivers)
        external
        returns (uint128 collectableAmt, uint128 splitAmt);

    /// @notice Returns the current splittable balance for an account and token.
    function splittable(uint256 accountId, IERC20 erc20) external view returns (uint128 amt);
}
```

---

## Code Snippets

### Full `CoreProtocol.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAddressDriver} from "./interfaces/IAddressDriver.sol";
import {IDrips} from "./interfaces/IDrips.sol";
import {SplitsReceiver} from "./interfaces/DripsStructs.sol";

/// @title CoreProtocol
/// @notice Entry point for funding. Automatically splits received funds
///         across sub-projects via Drips V2 splits.
contract CoreProtocol {
    using SafeERC20 for IERC20;

    uint32 public constant TOTAL_WEIGHT = 1_000_000;

    IAddressDriver public immutable addressDriver;
    IDrips public immutable drips;

    SplitsReceiver[] private _splits;

    /// @param _addressDriver Drips V2 AddressDriver address
    /// @param _drips         Drips V2 core contract address
    /// @param receivers      Sub-project accountIds + weights (sorted asc by accountId, sum <= TOTAL_WEIGHT)
    constructor(address _addressDriver, address _drips, SplitsReceiver[] memory receivers) {
        addressDriver = IAddressDriver(_addressDriver);
        drips = IDrips(_drips);

        uint32 total;
        for (uint256 i; i < receivers.length; i++) {
            total += receivers[i].weight;
            _splits.push(receivers[i]);
        }
        require(total <= TOTAL_WEIGHT, "weights overflow");

        addressDriver.setSplits(receivers);
    }

    /// @notice Distribute this contract's splittable balance to sub-projects.
    function distributeYield(IERC20 token) external {
        drips.split(_accountId(), token, _splits);
    }

    /// @notice Collect remaining (non-split) funds to `to`.
    function collect(IERC20 token, address to) external {
        addressDriver.collect(token, to);
    }

    /// @notice Fund a sub-project directly with a one-time give.
    function give(uint256 receiverId, IERC20 token, uint128 amt) external {
        token.safeTransferFrom(msg.sender, address(this), amt);
        token.forceApprove(address(addressDriver), amt);
        addressDriver.give(receiverId, token, amt);
    }

    /// @notice Returns this contract's Drips account ID.
    function accountId() external view returns (uint256) {
        return _accountId();
    }

    /// @notice Returns the stored splits configuration.
    function splitsReceivers() external view returns (SplitsReceiver[] memory) {
        return _splits;
    }

    function _accountId() internal view returns (uint256) {
        return addressDriver.calcAccountId(address(this));
    }
}
```

### Checking the splittable balance before distributing

```solidity
IDrips dripsContract = IDrips(DRIPS_ADDRESS);
uint256 coreAccountId = protocol.accountId();
uint128 pending = dripsContract.splittable(coreAccountId, IERC20(TOKEN_ADDRESS));

if (pending > 0) {
    protocol.distributeYield(IERC20(TOKEN_ADDRESS));
}
```

### Funding a sub-project directly

```solidity
IERC20 token = IERC20(TOKEN_ADDRESS);
uint128 amount = 500e18;

token.approve(address(protocol), amount);
protocol.give(SUB_PROJECT_A_ACCOUNT_ID, token, amount);
```

---

## Deployment

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed
- An RPC URL (e.g. Alchemy, Infura, or a local Anvil node)
- A funded deployer private key

### 1. Build

```shell
forge build
```

### 2. Write a deploy script

Create `script/Deploy.s.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {CoreProtocol} from "../src/CoreProtocol.sol";
import {SplitsReceiver} from "../src/interfaces/DripsStructs.sol";

contract Deploy is Script {
    // Ethereum Mainnet
    address constant ADDRESS_DRIVER = 0x1455d9bD6B98f95dd8FEB2b3D60ed825fcef0610;
    address constant DRIPS           = 0xd0Dd053392db676D57317CD4fe96Fc2cCf42D0b4;

    function run() external {
        SplitsReceiver[] memory receivers = new SplitsReceiver[](3);
        // accountIds MUST be sorted ascending
        receivers[0] = SplitsReceiver({ accountId: SUB_A_ID, weight: 400_000 }); // 40%
        receivers[1] = SplitsReceiver({ accountId: SUB_B_ID, weight: 300_000 }); // 30%
        receivers[2] = SplitsReceiver({ accountId: SUB_C_ID, weight: 300_000 }); // 30%

        vm.startBroadcast();
        new CoreProtocol(ADDRESS_DRIVER, DRIPS, receivers);
        vm.stopBroadcast();
    }
}
```

### 3. Deploy

```shell
forge script script/Deploy.s.sol \
  --rpc-url <RPC_URL> \
  --private-key <PRIVATE_KEY> \
  --broadcast \
  --verify
```

For Sepolia, swap in the testnet addresses:

```shell
forge script script/Deploy.s.sol \
  --rpc-url <SEPOLIA_RPC_URL> \
  --private-key <PRIVATE_KEY> \
  --broadcast
```

---

## Deployed Addresses

### Ethereum Mainnet

| Contract        | Address                                      |
|-----------------|----------------------------------------------|
| `Drips`         | `0xd0Dd053392db676D57317CD4fe96Fc2cCf42D0b4` |
| `AddressDriver` | `0x1455d9bD6B98f95dd8FEB2b3D60ed825fcef0610` |

### Sepolia Testnet

| Contract        | Address                                      |
|-----------------|----------------------------------------------|
| `Drips`         | `0x74A32a38D945b9527524900429b083547DeB9bF4` |
| `AddressDriver` | `0x70E1E1437AeFe8024B6780C94490662b45C3B567` |

---

## Testing

Tests are written with [Forge](https://book.getfoundry.sh/forge/tests) and use `vm.mockCall` to isolate `CoreProtocol` from live Drips contracts.

### Run all tests

```shell
forge test -v
```

### Test coverage

| Test | What it verifies |
|---|---|
| `test_accountId` | `accountId()` returns the value from `calcAccountId` |
| `test_splitsReceivers` | Stored receivers match what was passed to the constructor |
| `test_distributeYield` | `Drips.split()` is called with the correct account ID and token |
| `test_collect` | `AddressDriver.collect()` is forwarded with the correct arguments |
| `test_give` | Tokens are pulled from caller and forwarded to `AddressDriver.give()` |
| `test_constructor_revert_weightsOverflow` | Constructor reverts when weights exceed `1_000_000` |

### Example test output

```
Ran 6 tests for test/CoreProtocol.t.sol:CoreProtocolTest
[PASS] test_accountId() (gas: 9021)
[PASS] test_collect() (gas: 18756)
[PASS] test_constructor_revert_weightsOverflow() (gas: 113483)
[PASS] test_distributeYield() (gas: 36760)
[PASS] test_give() (gas: 23339)
[PASS] test_splitsReceivers() (gas: 25873)
Suite result: ok. 6 passed; 0 failed; 0 skipped
```

---

## Development

**Prerequisites:** [Foundry](https://book.getfoundry.sh/getting-started/installation)

```shell
# Install dependencies
forge install

# Build
forge build

# Run tests
forge test -v

# Format code
forge fmt

# Gas snapshot
forge snapshot

# Start a local node
anvil

# Interact with a deployed contract
cast call <CONTRACT_ADDRESS> "accountId()(uint256)" --rpc-url <RPC_URL>
cast call <CONTRACT_ADDRESS> "splitsReceivers()((uint256,uint32)[])" --rpc-url <RPC_URL>
```

### Project structure

```
.
├── foundry.toml                  # Foundry config + remappings
├── lib/
│   ├── forge-std/                # Foundry test utilities
│   └── openzeppelin-contracts/   # OZ SafeERC20, IERC20
├── src/
│   ├── CoreProtocol.sol          # Main contract
│   └── interfaces/
│       ├── DripsStructs.sol      # SplitsReceiver struct
│       ├── IAddressDriver.sol    # AddressDriver interface
│       └── IDrips.sol            # Drips core interface
├── test/
│   └── CoreProtocol.t.sol        # Forge unit tests
└── script/
    └── Deploy.s.sol              # Deployment script
```

---

## Tech Stack

| Tool / Library | Version | Purpose |
|---|---|---|
| Solidity | `^0.8.20` | Smart contract language |
| Foundry (Forge) | latest | Build, test, deploy |
| Foundry (Cast) | latest | CLI contract interaction |
| Foundry (Anvil) | latest | Local EVM node |
| OpenZeppelin Contracts | latest | `SafeERC20`, `IERC20` |
| Drips V2 | `v2_ethereum_deploy` | Splits and streaming protocol |
