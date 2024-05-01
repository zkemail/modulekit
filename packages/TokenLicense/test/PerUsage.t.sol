// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Base.t.sol";
import "forge-std/console2.sol";

contract PerUsageTest is BaseTest {
    function setUp() public override {
        super.setUp();

        licenseMgr.setSubscriptionConfig({
            module: module.addr,
            pricePerSecond: uint128(10),
            minSubTime: uint128(1 * 7 days)
        });
    }

    function test_single() public {
        vm.startPrank(module.addr);

        licenseMgr.permitClaim(
            instance.account,
            address(0),
            Claim({
                claimType: ClaimType.SingleCharge,
                module: module.addr,
                smartAccount: instance.account,
                payToken: IERC20(address(usdc)),
                usdAmount: 100 ether,
                data: ""
            })
        );

        vm.stopPrank();
    }

    function test_single_swap() public {
        vm.startPrank(module.addr);

        licenseMgr.permitClaim(
            instance.account,
            address(0),
            Claim({
                claimType: ClaimType.SingleCharge,
                module: module.addr,
                smartAccount: instance.account,
                payToken: IERC20(address(weth)),
                usdAmount: 6_050_000,
                data: ""
            })
        );

        vm.stopPrank();
    }
}
