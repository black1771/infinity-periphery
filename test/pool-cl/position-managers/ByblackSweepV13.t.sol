// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Currency} from "infinity-core/src/types/Currency.sol";
import {IHooks} from "infinity-core/src/interfaces/IHooks.sol";
import {PoolId} from "infinity-core/src/types/PoolId.sol";
import {PoolKey} from "infinity-core/src/types/PoolKey.sol";
import {ICLPoolManager} from "infinity-core/src/pool-cl/interfaces/ICLPoolManager.sol";
import {IVault} from "infinity-core/src/interfaces/IVault.sol";

import {PosmTestSetup} from "../shared/PosmTestSetup.sol";
import {Planner, Plan} from "../../../src/libraries/Planner.sol";
import {Actions} from "../../../src/libraries/Actions.sol";

contract ByblackSweepV13 is Test, PosmTestSetup {
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        deployPosmHookSavesDelta();

        (IVault vault, ICLPoolManager manager, PoolKey memory key, PoolId poolId) =
            createFreshPool(IHooks(address(hook)), 3000, SQRT_RATIO_1_1);

        currency0 = key.currency0;
        currency1 = key.currency1;

        deployAndApproveRouter(vault, manager);
        deployAndApprovePosm(vault, manager);

        seedBalance(alice);
    }

    function test_byblack_sweep_leftoverTokens() public {
        address token = Currency.unwrap(currency0);
        uint256 amount = 1000;

        vm.prank(alice);
        IERC20(token).transfer(address(lpm), amount);

        uint256 bobBefore = IERC20(token).balanceOf(bob);

        Plan memory plan = Planner.init();
        plan.add(Actions.SWEEP, abi.encode(currency0, bob));

        vm.prank(bob);
        lpm.modifyLiquidities(plan.encode(), block.timestamp + 100);

        uint256 bobAfter = IERC20(token).balanceOf(bob);

        assertEq(bobAfter - bobBefore, amount);
        assertEq(IERC20(token).balanceOf(address(lpm)), 0);
    }
}
