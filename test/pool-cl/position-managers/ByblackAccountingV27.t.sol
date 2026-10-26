// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ByblackSequenceV24} from "./ByblackSequenceV24.t.sol";
import {Actions} from "../../../src/libraries/Actions.sol";
import {Planner, Plan} from "../../../src/libraries/Planner.sol";

contract ByblackAccountingV27 is ByblackSequenceV24 {

    function accountingPayload(
        uint256 first,
        uint256 second
    ) internal view returns (bytes memory) {
        Plan memory plan = Planner.init();

        plan.add(
            Actions.CL_DECREASE_LIQUIDITY,
            abi.encode(
                tokenId,
                first,
                uint128(0),
                uint128(0),
                bytes("")
            )
        );

        if (second > 0) {
            plan.add(
                Actions.CL_DECREASE_LIQUIDITY,
                abi.encode(
                    tokenId,
                    second,
                    uint128(0),
                    uint128(0),
                    bytes("")
                )
            );
        }

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

    function test_V27_singleDecreaseAccounting() public {
        uint256 beforeLiquidity =
            lpm.getPositionLiquidity(tokenId);

        uint256 amount = beforeLiquidity / 4;

        vm.prank(bob);
        lpm.modifyLiquidities(
            accountingPayload(amount, 0),
            block.timestamp + 100
        );

        assertEq(
            lpm.getPositionLiquidity(tokenId),
            beforeLiquidity - amount,
            "V27: single decrease accounting mismatch"
        );

        assertEq(lpm.ownerOf(tokenId), bob);
    }

    function test_V27_doubleDecreaseAccounting() public {
        uint256 beforeLiquidity =
            lpm.getPositionLiquidity(tokenId);

        uint256 first = beforeLiquidity / 4;
        uint256 second = beforeLiquidity / 3;

        vm.prank(bob);
        lpm.modifyLiquidities(
            accountingPayload(first, second),
            block.timestamp + 100
        );

        assertEq(
            lpm.getPositionLiquidity(tokenId),
            beforeLiquidity - first - second,
            "V27: double decrease accounting mismatch"
        );

        assertEq(lpm.ownerOf(tokenId), bob);
    }

    function test_V27_overdrawMustRevertAtomically() public {
        uint256 beforeLiquidity =
            lpm.getPositionLiquidity(tokenId);

        uint256 first = beforeLiquidity / 2;
        uint256 second = beforeLiquidity;

        vm.prank(bob);
        vm.expectRevert();

        lpm.modifyLiquidities(
            accountingPayload(first, second),
            block.timestamp + 100
        );

        assertEq(
            lpm.getPositionLiquidity(tokenId),
            beforeLiquidity,
            "V27: liquidity changed after failed overdraw"
        );

        assertEq(
            lpm.ownerOf(tokenId),
            bob,
            "V27: ownership changed after failed overdraw"
        );
    }
}
