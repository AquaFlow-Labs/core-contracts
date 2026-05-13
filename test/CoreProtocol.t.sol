// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {CoreProtocol} from "../src/CoreProtocol.sol";
import {IAddressDriver} from "../src/interfaces/IAddressDriver.sol";
import {IDrips} from "../src/interfaces/IDrips.sol";
import {SplitsReceiver} from "../src/interfaces/DripsStructs.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CoreProtocolTest is Test {
    CoreProtocol protocol;

    address mockDriver = makeAddr("addressDriver");
    address mockDrips  = makeAddr("drips");
    address mockToken  = makeAddr("token");
    address user       = makeAddr("user");

    uint256 constant ACCOUNT_ID = 42;

    SplitsReceiver[] receivers;

    function setUp() public {
        receivers.push(SplitsReceiver(100, 400_000)); // 40%
        receivers.push(SplitsReceiver(200, 300_000)); // 30%
        receivers.push(SplitsReceiver(300, 300_000)); // 30%

        // Mock calcAccountId and setSplits called in constructor
        vm.mockCall(mockDriver, abi.encodeWithSelector(IAddressDriver.calcAccountId.selector), abi.encode(ACCOUNT_ID));
        vm.mockCall(mockDriver, abi.encodeWithSelector(IAddressDriver.setSplits.selector), abi.encode());

        protocol = new CoreProtocol(mockDriver, mockDrips, receivers);
    }

    function test_accountId() public view {
        assertEq(protocol.accountId(), ACCOUNT_ID);
    }

    function test_splitsReceivers() public view {
        SplitsReceiver[] memory r = protocol.splitsReceivers();
        assertEq(r.length, 3);
        assertEq(r[0].accountId, 100);
        assertEq(r[0].weight, 400_000);
    }

    function test_distributeYield() public {
        vm.mockCall(
            mockDrips,
            abi.encodeWithSelector(IDrips.split.selector, ACCOUNT_ID, IERC20(mockToken)),
            abi.encode(uint128(1000), uint128(0))
        );
        protocol.distributeYield(IERC20(mockToken));
    }

    function test_collect() public {
        vm.mockCall(
            mockDriver,
            abi.encodeWithSelector(IAddressDriver.collect.selector, IERC20(mockToken), user),
            abi.encode(uint128(500))
        );
        protocol.collect(IERC20(mockToken), user);
    }

    function test_give() public {
        uint128 amt = 1000;
        vm.mockCall(mockToken, abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
        vm.mockCall(mockToken, abi.encodeWithSelector(bytes4(keccak256("approve(address,uint256)"))), abi.encode(true));
        vm.mockCall(
            mockDriver,
            abi.encodeWithSelector(IAddressDriver.give.selector, uint256(100), IERC20(mockToken), amt),
            abi.encode()
        );
        vm.prank(user);
        protocol.give(100, IERC20(mockToken), amt);
    }

    function test_constructor_revert_weightsOverflow() public {
        SplitsReceiver[] memory bad = new SplitsReceiver[](1);
        bad[0] = SplitsReceiver(1, 1_000_001);

        vm.mockCall(mockDriver, abi.encodeWithSelector(IAddressDriver.setSplits.selector), abi.encode());
        vm.expectRevert("weights overflow");
        new CoreProtocol(mockDriver, mockDrips, bad);
    }
}
