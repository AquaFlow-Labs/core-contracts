// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice A splits receiver entry. Weights must sum to <= 1_000_000.
struct SplitsReceiver {
    uint256 accountId;
    uint32 weight;
}
