// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SplitsReceiver} from "./DripsStructs.sol";

interface IAddressDriver {
    function setSplits(SplitsReceiver[] calldata receivers) external;
    function give(uint256 receiverId, IERC20 erc20, uint128 amt) external;
    function collect(IERC20 erc20, address transferTo) external returns (uint128 amt);
    function calcAccountId(address userAddr) external view returns (uint256 accountId);
}
