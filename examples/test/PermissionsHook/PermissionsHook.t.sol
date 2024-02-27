// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "@rhinestone/modulekit/src/ModuleKit.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import {
    SessionData,
    SessionKeyManagerLib
} from "@rhinestone/sessionkeymanager/src/SessionKeyManagerLib.sol";
import { MockExecutor, MockERC20 } from "@rhinestone/modulekit/src/Mocks.sol";
import { Solarray } from "solarray/Solarray.sol";

import {
    MODULE_TYPE_HOOK, MODULE_TYPE_EXECUTOR
} from "@rhinestone/modulekit/src/external/ERC7579.sol";
import { PermissionsHook, IERC7579Account } from "src/PermissionsHook/PermissionsHookV2.sol";

import { SpendingLimit } from "src/PermissionsHook/subHooks/SpendingLimit.sol";

contract PermissionsHookTest is RhinestoneModuleKit, Test {
    using ModuleKitHelpers for *;
    using ModuleKitUserOp for *;

    // Account instance and hook
    AccountInstance internal instance;
    MockERC20 internal token;
    PermissionsHook internal permissionsHook;

    // Mock executors
    MockExecutor internal executorDisallowed;
    MockExecutor internal executorAllowed;

    SpendingLimit internal spendingLimit;

    address activeExecutor;
    bool activeCallSuccess;

    function setUp() public {
        init();

        permissionsHook = new PermissionsHook();
        vm.label(address(permissionsHook), "permissionsHook");

        spendingLimit = new SpendingLimit(address(permissionsHook));
        vm.label(address(spendingLimit), "SubHook:SpendingLimit");
        executorDisallowed = new MockExecutor();
        vm.label(address(executorDisallowed), "executorDisallowed");
        executorAllowed = new MockExecutor();
        vm.label(address(executorAllowed), "executorAllowed");

        instance = makeAccountInstance("PermissionsHookTestAccount");
        deal(address(instance.account), 100 ether);

        token = new MockERC20();
        token.initialize("Mock Token", "MTK", 18);
        deal(address(token), instance.account, 100 ether);

        setUpPermissionsHook();
    }

    function setUpPermissionsHook() internal {
        console2.log("setting up permissions hook");
        instance.installModule({
            moduleTypeId: MODULE_TYPE_EXECUTOR,
            module: address(executorDisallowed),
            data: ""
        });
        instance.installModule({
            moduleTypeId: MODULE_TYPE_EXECUTOR,
            module: address(executorAllowed),
            data: ""
        });

        address[] memory modules = new address[](3);
        modules[0] = address(executorDisallowed);
        modules[1] = address(executorAllowed);
        modules[2] = address(instance.defaultValidator);

        PermissionsHook.AccessFlags[] memory permissions = new PermissionsHook.AccessFlags[](3);
        permissions[0] = PermissionsHook.AccessFlags({
            selfCall: false,
            moduleCall: false,
            hasAllowedTargets: true,
            sendValue: false,
            hasAllowedFunctions: true,
            erc20Transfer: false,
            erc721Transfer: false,
            moduleConfig: false
        });

        permissions[1] = PermissionsHook.AccessFlags({
            selfCall: true,
            moduleCall: true,
            hasAllowedTargets: false,
            sendValue: true,
            hasAllowedFunctions: false,
            erc20Transfer: true,
            erc721Transfer: true,
            moduleConfig: true
        });

        permissions[2] = PermissionsHook.AccessFlags({
            selfCall: true,
            moduleCall: true,
            hasAllowedTargets: false,
            sendValue: true,
            hasAllowedFunctions: false,
            erc20Transfer: true,
            erc721Transfer: true,
            moduleConfig: true
        });

        console2.log("installing module");
        instance.installModule({
            moduleTypeId: MODULE_TYPE_HOOK,
            module: address(permissionsHook),
            data: abi.encode(modules, permissions)
        });
        console2.log("installed");

        vm.prank(instance.account);
        address[] memory subHooks = new address[](1);
        subHooks[0] = address(spendingLimit);

        permissionsHook.installGlobalHooks(subHooks);
    }

    modifier performWithBothExecutors() {
        // Disallowed executor
        activeExecutor = address(executorDisallowed);
        _;
        assertFalse(activeCallSuccess);

        // Allowed executor
        activeExecutor = address(executorAllowed);
        _;
        assertTrue(activeCallSuccess);
    }

    function test_selfCall() public performWithBothExecutors {
        address target = instance.account;
        uint256 value = 0;
        bytes memory callData = abi.encodeWithSelector(
            IERC7579Account.execute.selector,
            bytes32(0),
            abi.encodePacked(makeAddr("target"), uint256(1 ether), bytes(""))
        );

        bytes memory executorCallData = abi.encodeWithSelector(
            MockExecutor.exec.selector, instance.account, target, value, callData
        );

        (bool success, bytes memory result) = activeExecutor.call(executorCallData);
        activeCallSuccess = success;
    }

    function test_sendValue() public performWithBothExecutors {
        address target = makeAddr("target");
        uint256 value = 1 ether;
        bytes memory callData = "";

        bytes memory executorCallData = abi.encodeWithSelector(
            MockExecutor.exec.selector, instance.account, target, value, callData
        );

        (bool success, bytes memory result) = activeExecutor.call(executorCallData);
        activeCallSuccess = success;
    }

    function test_sendValue_4337() public performWithBothExecutors {
        address target = makeAddr("target");
        uint256 balanceBefore = target.balance;
        uint256 value = 1 ether;
        bytes memory callData = "";

        instance.exec({ target: address(target), value: value, callData: callData });
        assertEq(target.balance, balanceBefore + value);
    }

    function test_sendERC20() public {
        address receiver = makeAddr("receiver");
        vm.prank(instance.account);
        spendingLimit.setLimit(address(token), 200);
        bytes memory callData = abi.encodeCall(IERC20.transfer, (receiver, 150));

        instance.exec({ target: address(token), value: 0, callData: callData });

        assertEq(token.balanceOf(receiver), 150);

        vm.expectRevert();
        instance.exec({ target: address(token), value: 0, callData: callData });
    }
}
