// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAddressDriver} from "./interfaces/IAddressDriver.sol";
import {IDrips} from "./interfaces/IDrips.sol";
import {SplitsReceiver} from "./interfaces/DripsStructs.sol";

/// @title CoreProtocol
/// @notice Entry point for funding. Automatically splits received funds
///         across three sub-projects via Drips V2 splits.
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

    function accountId() external view returns (uint256) {
        return _accountId();
    }

    function splitsReceivers() external view returns (SplitsReceiver[] memory) {
        return _splits;
    }

    function _accountId() internal view returns (uint256) {
        return addressDriver.calcAccountId(address(this));
    }
}
