// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PermitTest} from "./Permit.t.sol";
import {UnorderedNonce} from "../../../src/pool-cl/base/UnorderedNonce.sol";

contract ByblackPermitV26 is PermitTest {

    function createAlicePosition()
        internal
        returns (uint256 tokenId)
    {
        tokenId = lpm.nextTokenId();

        vm.prank(alice);
        mint(
            key,
            -300,
            300,
            1e18,
            alice,
            ZERO_BYTES
        );

        assertEq(lpm.ownerOf(tokenId), alice);
    }

    function signedPermit(
        uint256 tokenId,
        uint256 nonce,
        uint256 deadline
    )
        internal
        returns (bytes memory signature)
    {
        bytes32 digest =
            getDigest(bob, tokenId, nonce, deadline);

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(alicePK, digest);

        signature = abi.encodePacked(r, s, v);
    }

    function test_V26_usedSignatureCannotReplay() public {
        uint256 tokenId = createAlicePosition();

        uint256 nonce = 1001;
        uint256 deadline = block.timestamp + 1000;

        bytes memory signature =
            signedPermit(tokenId, nonce, deadline);

        // First use must succeed.
        lpm.permit(
            bob,
            tokenId,
            deadline,
            nonce,
            signature
        );

        assertEq(lpm.getApproved(tokenId), bob);

        // Clear the approval to make a replay meaningful.
        vm.prank(alice);
        lpm.approve(address(0), tokenId);

        assertEq(
            lpm.getApproved(tokenId),
            address(0)
        );

        // The old signature must not restore approval.
        vm.expectRevert(
            UnorderedNonce.NonceAlreadyUsed.selector
        );

        lpm.permit(
            bob,
            tokenId,
            deadline,
            nonce,
            signature
        );

        assertEq(
            lpm.getApproved(tokenId),
            address(0),
            "V26: replay restored approval"
        );
    }

    function test_V26_oldOwnerSignatureAfterTransfer()
        public
    {
        uint256 tokenId = createAlicePosition();

        uint256 nonce = 1002;
        uint256 deadline = block.timestamp + 1000;

        bytes memory signature =
            signedPermit(tokenId, nonce, deadline);

        // Transfer before using Alice's signature.
        vm.prank(alice);
        lpm.transferFrom(alice, bob, tokenId);

        assertEq(lpm.ownerOf(tokenId), bob);

        // Alice's signature must not authorize a
        // new approval after Bob becomes the owner.
        vm.expectRevert();

        lpm.permit(
            bob,
            tokenId,
            deadline,
            nonce,
            signature
        );

        assertEq(
            lpm.getApproved(tokenId),
            address(0),
            "V26: stale signature granted approval"
        );
    }

    function test_V26_expiredSignatureRejected() public {
        uint256 tokenId = createAlicePosition();

        uint256 nonce = 1003;
        uint256 deadline = block.timestamp + 100;

        bytes memory signature =
            signedPermit(tokenId, nonce, deadline);

        vm.warp(deadline + 1);

        vm.expectRevert();

        lpm.permit(
            bob,
            tokenId,
            deadline,
            nonce,
            signature
        );

        assertEq(
            lpm.getApproved(tokenId),
            address(0),
            "V26: expired signature granted approval"
        );
    }
}
