// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IHooks} from "infinity-core/src/interfaces/IHooks.sol";
import {PoolId} from "infinity-core/src/types/PoolId.sol";
import {PoolKey} from "infinity-core/src/types/PoolKey.sol";
import {ICLPoolManager} from "infinity-core/src/pool-cl/interfaces/ICLPoolManager.sol";
import {IVault} from "infinity-core/src/interfaces/IVault.sol";

import {PosmTestSetup} from "../shared/PosmTestSetup.sol";
import {Actions} from "../../../src/libraries/Actions.sol";
import {Planner, Plan} from "../../../src/libraries/Planner.sol";

contract ByblackOperatorV22 is PosmTestSetup {
    address alice = makeAddr("V22_ALICE");
    address bob = makeAddr("V22_BOB");
    address charlie = makeAddr("V22_CHARLIE");

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

    function transferToBob() internal {
        vm.prank(alice);
        lpm.transferFrom(alice, bob, tokenId);

        assertEq(lpm.ownerOf(tokenId), bob);
    }

    function assertPositionSafe() internal view {
        assertEq(
            lpm.ownerOf(tokenId),
            bob,
            "V22: NFT ownership changed"
        );

        assertEq(
            lpm.getPositionLiquidity(tokenId),
            initialLiquidity,
            "V22: liquidity changed"
        );
    }

    function test_V22_tokenApprovalCleared() public {
        vm.prank(alice);
        lpm.approve(charlie, tokenId);

        assertEq(lpm.getApproved(tokenId), charlie);

        transferToBob();

        assertEq(
            lpm.getApproved(tokenId),
            address(0),
            "V22: token approval survived transfer"
        );

        assertPositionSafe();
    }

    function test_V22_oldApprovedCannotTransfer() public {
        vm.prank(alice);
        lpm.approve(charlie, tokenId);

        transferToBob();

        vm.prank(charlie);
        vm.expectRevert();

        lpm.transferFrom(bob, charlie, tokenId);

        assertPositionSafe();
    }

    function test_V22_oldOperatorCannotTransfer() public {
        vm.prank(alice);
        lpm.setApprovalForAll(charlie, true);

        assertTrue(
            lpm.isApprovedForAll(alice, charlie)
        );

        transferToBob();

        // Alice's approval may still exist.
        assertTrue(
            lpm.isApprovedForAll(alice, charlie)
        );

        // But Bob did not authorize Charlie.
        assertFalse(
            lpm.isApprovedForAll(bob, charlie)
        );

        vm.prank(charlie);
        vm.expectRevert();

        lpm.transferFrom(bob, charlie, tokenId);

        assertPositionSafe();
    }

    function test_V22_oldOperatorCannotApprove() public {
        vm.prank(alice);
        lpm.setApprovalForAll(charlie, true);

        transferToBob();

        vm.prank(charlie);
        vm.expectRevert();

        lpm.approve(charlie, tokenId);

        assertEq(
            lpm.getApproved(tokenId),
            address(0),
            "V22: old operator granted approval"
        );

        assertPositionSafe();
    }

    function test_V22_oldOperatorCannotDecrease() public {
        vm.prank(alice);
        lpm.setApprovalForAll(charlie, true);

        transferToBob();

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

        vm.prank(charlie);
        vm.expectRevert();

        lpm.modifyLiquidities(
            plan.encode(),
            block.timestamp + 100
        );

        assertPositionSafe();
    }
}
