// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "@rhinestone/modulekit/src/ModuleKit.sol";
import {
    SessionData,
    SessionKeyManagerLib
} from "@rhinestone/sessionkeymanager/src/SessionKeyManagerLib.sol";
import { MockExecutor } from "@rhinestone/modulekit/src/Mocks.sol";
import { Solarray } from "solarray/Solarray.sol";

import {
    MODULE_TYPE_HOOK, MODULE_TYPE_EXECUTOR
} from "@rhinestone/modulekit/src/external/ERC7579.sol";
import { PermissionsHook, IERC7579Account } from "src/PermissionsHook/PermissionsHook.sol";

contract PermissionsHookTest is RhinestoneModuleKit, Test {
    using ModuleKitHelpers for *;
    using ModuleKitUserOp for *;

    bytes1 internal constant FALSE_CONSTANT = 0x00;
    bytes1 internal constant TRUE_CONSTANT = 0x01;

    // Account instance and hook
    AccountInstance internal instance;
    PermissionsHook internal permissionsHook;

    // Mock executors
    MockExecutor internal executorDisallowed;
    MockExecutor internal executorAllowed;

    address activeExecutor;
    bool activeCallSuccess;

    function setUp() public {
        init();

        permissionsHook = new PermissionsHook();
        vm.label(address(permissionsHook), "permissionsHook");
        executorDisallowed = new MockExecutor();
        vm.label(address(executorDisallowed), "executorDisallowed");
        executorAllowed = new MockExecutor();
        vm.label(address(executorAllowed), "executorAllowed");

        instance = makeAccountInstance("PermissionsHookTestAccount");
        deal(address(instance.account), 100 ether);

        setUpPermissionsHook();
    }

    function setUpPermissionsHook() internal {
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

        address[] memory executors = new address[](2);
        executors[0] = address(executorDisallowed);
        executors[1] = address(executorAllowed);

        PermissionsHook.ModulePermissions[] memory permissions =
            new PermissionsHook.ModulePermissions[](2);
        permissions[0] = PermissionsHook.ModulePermissions({
            selfCall: FALSE_CONSTANT,
            moduleCall: FALSE_CONSTANT,
            hasAllowedTargets: TRUE_CONSTANT,
            sendValue: FALSE_CONSTANT,
            hasAllowedFunctions: TRUE_CONSTANT,
            erc20Transfer: FALSE_CONSTANT,
            erc721Transfer: FALSE_CONSTANT,
            moduleConfig: FALSE_CONSTANT,
            allowedFunctions: new bytes4[](0),
            allowedTargets: new address[](0)
        });

        permissions[1] = PermissionsHook.ModulePermissions({
            selfCall: TRUE_CONSTANT,
            moduleCall: TRUE_CONSTANT,
            hasAllowedTargets: FALSE_CONSTANT,
            sendValue: TRUE_CONSTANT,
            hasAllowedFunctions: FALSE_CONSTANT,
            erc20Transfer: TRUE_CONSTANT,
            erc721Transfer: TRUE_CONSTANT,
            moduleConfig: TRUE_CONSTANT,
            allowedFunctions: new bytes4[](0),
            allowedTargets: new address[](0)
        });

        instance.installModule({
            moduleTypeId: MODULE_TYPE_HOOK,
            module: address(permissionsHook),
            data: abi.encode(executors, permissions)
        });
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
}
