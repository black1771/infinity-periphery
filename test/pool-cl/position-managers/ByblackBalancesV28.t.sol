// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ByblackSequenceV24} from "./ByblackSequenceV24.t.sol";
import {Actions} from "../../../src/libraries/Actions.sol";
import {Planner, Plan} from "../../../src/libraries/Planner.sol";

contract ByblackBalancesV28 is ByblackSequenceV24 {

    function payoutPayload()
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

        // Zero threshold: take positive deltas.
        plan.add(
            Actions.CLEAR_OR_TAKE,
            abi.encode(currency0, uint256(0))
        );

        plan.add(
            Actions.CLEAR_OR_TAKE,
            abi.encode(currency1, uint256(0))
        );

        return plan.encode();
    }


    function test_V28_ownerReceivesTokens() public {
        uint256 bob0Before = currency0.balanceOf(bob);
        uint256 bob1Before = currency1.balanceOf(bob);

        uint256 liquidityBefore =
            lpm.getPositionLiquidity(tokenId);

        vm.prank(bob);
        lpm.modifyLiquidities(
            payoutPayload(),
            block.timestamp + 100
        );

        uint256 bob0After = currency0.balanceOf(bob);
        uint256 bob1After = currency1.balanceOf(bob);

        assertEq(
            lpm.getPositionLiquidity(tokenId),
            liquidityBefore - initialLiquidity / 2,
            "V28: liquidity accounting mismatch"
        );

        assertGe(
            bob0After,
            bob0Before,
            "V28: owner token0 balance decreased"
        );

        assertGe(
            bob1After,
            bob1Before,
            "V28: owner token1 balance decreased"
        );

        assertTrue(
            bob0After > bob0Before ||
            bob1After > bob1Before,
            "V28: owner received no tokens"
        );
    }

    function test_V28_unauthorizedBalancesUnchanged()
        public
    {
        uint256 bob0Before = currency0.balanceOf(bob);
        uint256 bob1Before = currency1.balanceOf(bob);

        uint256 charlie0Before =
            currency0.balanceOf(charlie);
        uint256 charlie1Before =
            currency1.balanceOf(charlie);

        uint256 liquidityBefore =
            lpm.getPositionLiquidity(tokenId);

        vm.prank(charlie);

        vm.expectRevert(
            abi.encodeWithSignature(
                "NotApproved(address)",
                charlie
            )
        );

        lpm.modifyLiquidities(
            payoutPayload(),
            block.timestamp + 100
        );

        assertEq(
            currency0.balanceOf(bob),
            bob0Before,
            "V28: bob token0 changed"
        );

        assertEq(
            currency1.balanceOf(bob),
            bob1Before,
            "V28: bob token1 changed"
        );

        assertEq(
            currency0.balanceOf(charlie),
            charlie0Before,
            "V28: charlie token0 changed"
        );

        assertEq(
            currency1.balanceOf(charlie),
            charlie1Before,
            "V28: charlie token1 changed"
        );

        assertEq(
            lpm.getPositionLiquidity(tokenId),
            liquidityBefore,
            "V28: liquidity changed after revert"
        );
    }

    function test_V28_oldOwnerReceivesNothing()
        public
    {
        uint256 alice0Before =
            currency0.balanceOf(alice);
        uint256 alice1Before =
            currency1.balanceOf(alice);

        vm.prank(bob);
        lpm.modifyLiquidities(
            payoutPayload(),
            block.timestamp + 100
        );

        assertEq(
            currency0.balanceOf(alice),
            alice0Before,
            "V28: old owner received token0"
        );

        assertEq(
            currency1.balanceOf(alice),
            alice1Before,
            "V28: old owner received token1"
        );
    }
}
