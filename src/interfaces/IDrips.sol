// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SplitsReceiver} from "./DripsStructs.sol";

interface IDrips {
    function split(uint256 accountId, IERC20 erc20, SplitsReceiver[] calldata currReceivers)
        external
        returns (uint128 collectableAmt, uint128 splitAmt);

    function splittable(uint256 accountId, IERC20 erc20) external view returns (uint128 amt);
}
