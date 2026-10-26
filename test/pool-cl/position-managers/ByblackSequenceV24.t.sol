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

contract ByblackSequenceV24 is PosmTestSetup {
    address alice = makeAddr("V23_ALICE");
    address bob = makeAddr("V23_BOB");
    address charlie = makeAddr("V23_CHARLIE");

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

        // Alice authorizes Charlie, then transfers to Bob.
        vm.prank(alice);
        lpm.setApprovalForAll(charlie, true);

        vm.prank(alice);
        lpm.transferFrom(alice, bob, tokenId);

        assertEq(lpm.ownerOf(tokenId), bob);
        assertFalse(lpm.isApprovedForAll(bob, charlie));
    }

    function decreasePayload()
        internal
        view
        returns (bytes memory)
    {
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

        plan.add(
            Actions.CLEAR_OR_TAKE,
            abi.encode(currency0, type(uint256).max)
        );

        plan.add(
            Actions.CLEAR_OR_TAKE,
            abi.encode(currency1, type(uint256).max)
        );

        return plan.encode();
    }

    function test_V23_unauthorizedErrorSelector() public {
        bytes memory payload = decreasePayload();

        uint256 beforeLiquidity =
            lpm.getPositionLiquidity(tokenId);

        vm.prank(charlie);

        (bool success, bytes memory returndata) =
            address(lpm).call(
                abi.encodeWithSelector(
                    lpm.modifyLiquidities.selector,
                    payload,
                    block.timestamp + 100
                )
            );

        assertFalse(
            success,
            "V23: unauthorized decrease succeeded"
        );

        assertGe(
            returndata.length,
            4,
            "V23: missing revert selector"
        );

        bytes4 selector;
        assembly {
            selector := mload(add(returndata, 32))
        }

        emit log_named_bytes32(
            "V23 unauthorized revert selector",
            bytes32(selector)
        );

        emit log_named_bytes(
            "V23 complete revert data",
            returndata
        );

        assertEq(
            lpm.ownerOf(tokenId),
            bob,
            "V23: NFT owner changed"
        );

        assertEq(
            lpm.getPositionLiquidity(tokenId),
            beforeLiquidity,
            "V23: liquidity changed"
        );
    }

    function test_V23_authorizedOwnerCanDecrease() public {
        bytes memory payload = decreasePayload();

        vm.prank(bob);

        lpm.modifyLiquidities(
            payload,
            block.timestamp + 100
        );

        assertEq(lpm.ownerOf(tokenId), bob);

        assertLt(
            lpm.getPositionLiquidity(tokenId),
            initialLiquidity,
            "V23: authorized liquidity did not decrease"
        );
    }

    function test_V23_oldOperatorCannotTransfer() public {
        vm.prank(charlie);
        vm.expectRevert();

        lpm.transferFrom(bob, charlie, tokenId);

        assertEq(lpm.ownerOf(tokenId), bob);
    }

    function doubleDecreasePayload()
        internal
        view
        returns (bytes memory)
    {
        Plan memory plan = Planner.init();

        uint256 amount = initialLiquidity / 4;

        plan.add(
            Actions.CL_DECREASE_LIQUIDITY,
            abi.encode(
                tokenId,
                amount,
                uint128(0),
                uint128(0),
                bytes("")
            )
        );

        plan.add(
            Actions.CL_DECREASE_LIQUIDITY,
            abi.encode(
                tokenId,
                amount,
                uint128(0),
                uint128(0),
                bytes("")
            )
        );

        plan.add(
            Actions.CLEAR_OR_TAKE,
            abi.encode(currency0, type(uint256).max)
        );

        plan.add(
            Actions.CLEAR_OR_TAKE,
            abi.encode(currency1, type(uint256).max)
        );

        return plan.encode();
    }

    function test_V24_exactUnauthorizedError() public {
        bytes memory payload = decreasePayload();

        vm.prank(charlie);

        vm.expectRevert(
            abi.encodeWithSignature(
                "NotApproved(address)",
                charlie
            )
        );

        lpm.modifyLiquidities(
            payload,
            block.timestamp + 100
        );
    }

    function test_V24_ownerDoubleDecrease() public {
        uint256 beforeLiquidity =
            lpm.getPositionLiquidity(tokenId);

        vm.prank(bob);

        lpm.modifyLiquidities(
            doubleDecreasePayload(),
            block.timestamp + 100
        );

        assertEq(
            lpm.getPositionLiquidity(tokenId),
            beforeLiquidity - 2 * (initialLiquidity / 4),
            "V24: incorrect liquidity after double decrease"
        );

        assertEq(lpm.ownerOf(tokenId), bob);
    }

    function test_V24_unauthorizedDoubleDecreaseAtomic() public {
        uint256 beforeLiquidity =
            lpm.getPositionLiquidity(tokenId);

        bytes memory payload = doubleDecreasePayload();

        vm.prank(charlie);

        vm.expectRevert(
            abi.encodeWithSignature(
                "NotApproved(address)",
                charlie
            )
        );

        lpm.modifyLiquidities(
            payload,
            block.timestamp + 100
        );

        assertEq(
            lpm.getPositionLiquidity(tokenId),
            beforeLiquidity,
            "V24: liquidity changed after revert"
        );

        assertEq(
            lpm.ownerOf(tokenId),
            bob,
            "V24: owner changed after revert"
        );
    }

}
