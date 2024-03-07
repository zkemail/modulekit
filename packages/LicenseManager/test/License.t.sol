// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "@rhinestone/modulekit/src/ModuleKit.sol";
import "@rhinestone/modulekit/src/Mocks.sol";
import "@rhinestone/modulekit/src/Helpers.sol";
import "@rhinestone/modulekit/src/Core.sol";

import {
    MODULE_TYPE_EXECUTOR,
    MODULE_TYPE_VALIDATOR
} from "@rhinestone/modulekit/src/external/ERC7579.sol";

import "src/PayMaster.sol";
import "./LicensedValidator.sol";

contract MockOracle is IOracle {
    function decimals() external view override returns (uint8) {
        return 18;
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        roundId = 0;
        answer = 100;
        startedAt = 0;
        updatedAt = block.timestamp;
        answeredInRound = 0;
    }
}

contract LicenseTest is RhinestoneModuleKit, Test {
    using ModuleKitHelpers for *;
    using ModuleKitSCM for *;
    using ModuleKitUserOp for *;

    AccountInstance internal instance;
    Account internal signer = makeAccount("signer");
    Account internal receiver = makeAccount("receiver");
    FeePayMaster internal feePayMaster;
    MockERC20 internal token;

    MockOracle internal oracle;

    LicensedValidator internal licensedValidator;

    function setUp() public {
        vm.warp(123_123_123);
        instance = makeAccountInstance("instance");
        vm.deal(instance.account, 100 ether);

        oracle = new MockOracle();

        token = new MockERC20();
        token.initialize("Mock Token", "MTK", 18);
        deal(address(token), instance.account, 100 ether);

        licensedValidator = new LicensedValidator(receiver.addr, address(token));
        vm.label(address(licensedValidator), "LicensedValidator");

        feePayMaster =
            new FeePayMaster(instance.aux.entrypoint, IERC20(address(token)), 18, oracle, oracle);
        vm.label(address(feePayMaster), "FeePayMaster");

        deal(instance.account, 100 ether);
        deal(address(this), 100 ether);
        instance.aux.entrypoint.depositTo{ value: 1 ether }(address(feePayMaster));

        instance.installModule({
            moduleTypeId: MODULE_TYPE_EXECUTOR,
            module: address(feePayMaster),
            data: ""
        });

        instance.installModule({
            moduleTypeId: MODULE_TYPE_VALIDATOR,
            module: address(licensedValidator),
            data: ""
        });

        vm.prank(instance.account);
        token.approve(address(feePayMaster), 100 ether);
    }

    function test_withpaymaster() public {
        address target = makeAddr("target");
        uint256 balanceBefore = target.balance;
        uint256 value = 1 ether;
        bytes memory callData = "";

        // instance.exec({ target: address(target), value: value, callData: callData });

        UserOpData memory userOpData =
            instance.getExecOps(target, value, callData, address(licensedValidator));
        // sign userOp with default signature

        userOpData.userOp.paymasterAndData = abi.encodePacked(
            address(feePayMaster),
            uint128(100_000),
            uint128(100_000),
            uint8(0),
            uint48(type(uint48).max),
            uint48(0)
        );

        uint256 depositBefore = instance.aux.entrypoint.balanceOf(address(feePayMaster));
        // send userOp to entrypoint
        userOpData.execUserOps();
        assertEq(target.balance, balanceBefore + value);

        uint256 depositAfter = instance.aux.entrypoint.balanceOf(address(feePayMaster));

        assertTrue(depositBefore <= depositAfter);

        assertTrue(token.balanceOf(receiver.addr) != 0);
    }
}
