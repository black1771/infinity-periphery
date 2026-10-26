// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {IHooks} from "infinity-core/src/interfaces/IHooks.sol";
import {PoolId} from "infinity-core/src/types/PoolId.sol";
import {PoolKey} from "infinity-core/src/types/PoolKey.sol";
import {ICLPoolManager} from "infinity-core/src/pool-cl/interfaces/ICLPoolManager.sol";
import {IVault} from "infinity-core/src/interfaces/IVault.sol";

import {PosmTestSetup} from "../shared/PosmTestSetup.sol";
import {Actions} from "../../../src/libraries/Actions.sol";
import {Planner, Plan} from "../../../src/libraries/Planner.sol";

contract ByblackTransferV21 is PosmTestSetup {
    address alice = makeAddr("V21_ALICE");
    address bob = makeAddr("V21_BOB");
    address charlie = makeAddr("V21_CHARLIE");

    uint256 tokenId;
    uint256 initialLiquidity;

    function setUp() public {
        deployPosmHookSavesDelta();

        (
            IVault vault,
            ICLPoolManager poolManager,
            PoolKey memory key,
            PoolId poolId
        ) = createFreshPool(
            IHooks(address(hook)),
            3000,
            SQRT_RATIO_1_1
        );

        currency0 = key.currency0;
        currency1 = key.currency1;

        deployAndApproveRouter(vault, poolManager);
        deployAndApprovePosm(vault, poolManager);

        seedBalance(alice);

        tokenId = lpm.nextTokenId();

        mint(
            key,
            -120,
            120,
            1e18,
            alice,
            ZERO_BYTES
        );

        initialLiquidity =
            lpm.getPositionLiquidity(tokenId);
    }

    function test_V21_oldOwnerCannotTransfer() public {
        // Alice transfers NFT to Bob.
        vm.prank(alice);
        lpm.transferFrom(alice, bob, tokenId);

        assertEq(lpm.ownerOf(tokenId), bob);

        // Alice must no longer be authorized.
        vm.prank(alice);
        vm.expectRevert();

        lpm.transferFrom(bob, charlie, tokenId);

        assertEq(
            lpm.ownerOf(tokenId),
            bob,
            "V21: old owner stole NFT"
        );
    }

    function test_V21_oldOwnerCannotApprove() public {
        vm.prank(alice);
        lpm.transferFrom(alice, bob, tokenId);

        vm.prank(alice);
        vm.expectRevert();

        lpm.approve(charlie, tokenId);

        assertEq(
            lpm.getApproved(tokenId),
            address(0),
            "V21: stale approval"
        );
    }

    function test_V21_oldOwnerCannotDecrease() public {
        vm.prank(alice);
        lpm.transferFrom(alice, bob, tokenId);

        Plan memory plan = Planner.init();

        plan.add(
            Actions.CL_DECREASE_LIQUIDITY,
            abi.encode(
                tokenId,
                initialLiquidity / 2,
                uint128(0),
                uint128(0),
                bytes("")
            )
        );

        vm.prank(alice);
        vm.expectRevert();

        lpm.modifyLiquidities(
            plan.encode(),
            block.timestamp + 100
        );

        assertEq(
            lpm.ownerOf(tokenId),
            bob,
            "V21: ownership changed"
        );

        assertEq(
            lpm.getPositionLiquidity(tokenId),
            initialLiquidity,
            "V21: old owner changed liquidity"
        );
    }

    function test_V21_approvalClearedOnTransfer() public {
        // Alice explicitly approves Charlie.
        vm.prank(alice);
        lpm.approve(charlie, tokenId);

        assertEq(lpm.getApproved(tokenId), charlie);

        // Alice transfers NFT to Bob.
        vm.prank(alice);
        lpm.transferFrom(alice, bob, tokenId);

        // Token-specific approval must be cleared.
        assertEq(
            lpm.getApproved(tokenId),
            address(0),
            "V21: approval survived transfer"
        );

        vm.prank(charlie);
        vm.expectRevert();

        lpm.transferFrom(bob, charlie, tokenId);

        assertEq(lpm.ownerOf(tokenId), bob);
    }
}
