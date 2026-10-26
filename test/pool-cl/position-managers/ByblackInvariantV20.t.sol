// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {IHooks} from "infinity-core/src/interfaces/IHooks.sol";
import {PoolId} from "infinity-core/src/types/PoolId.sol";
import {PoolKey} from "infinity-core/src/types/PoolKey.sol";
import {ICLPoolManager} from "infinity-core/src/pool-cl/interfaces/ICLPoolManager.sol";
import {IVault} from "infinity-core/src/interfaces/IVault.sol";

import {PosmTestSetup} from "../shared/PosmTestSetup.sol";
import {Actions} from "../../../src/libraries/Actions.sol";
import {Planner, Plan} from "../../../src/libraries/Planner.sol";
import {CLPositionManager} from "../../../src/pool-cl/CLPositionManager.sol";

contract ByblackHandlerV20 is Test {
    CLPositionManager public manager;

    address public alice;
    address public bob;

    uint256 public tokenId;
    uint256 public initialLiquidity;

    uint256 public decreaseAttempts;
    uint256 public transferAttempts;

    uint256 public unexpectedSuccesses;

    constructor(
        CLPositionManager _manager,
        address _alice,
        address _bob,
        uint256 _tokenId
    ) {
        manager = _manager;
        alice = _alice;
        bob = _bob;
        tokenId = _tokenId;

        initialLiquidity =
            manager.getPositionLiquidity(tokenId);
    }

    function attemptDecrease(uint96 rawAmount) public {
        uint256 amount = bound(
            uint256(rawAmount),
            1,
            initialLiquidity
        );

        Plan memory plan = Planner.init();

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

        decreaseAttempts++;

        vm.prank(bob);

        try manager.modifyLiquidities(
            plan.encode(),
            block.timestamp + 100
        ) {
            unexpectedSuccesses++;
        } catch {}
    }

    function attemptApprove() public {
        vm.prank(bob);

        try manager.approve(
            bob,
            tokenId
        ) {
            unexpectedSuccesses++;
        } catch {}
    }

    function attemptOperatorApproval() public {
        vm.prank(bob);

        try manager.setApprovalForAll(
            bob,
            true
        ) {
            // Bob may authorize his own NFTs.
            // This must not grant access to Alice's NFT.
        } catch {}
    }

    function attemptTransfer() public {
        transferAttempts++;

        vm.prank(bob);

        try manager.transferFrom(
            alice,
            bob,
            tokenId
        ) {
            unexpectedSuccesses++;
        } catch {}
    }
}

contract ByblackInvariantV20 is
    StdInvariant,
    PosmTestSetup
{
    ByblackHandlerV20 public handler;

    address alice = makeAddr("V20_ALICE");
    address bob = makeAddr("V20_BOB");

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

        handler = new ByblackHandlerV20(
            CLPositionManager(payable(address(lpm))),
            alice,
            bob,
            tokenId
        );

        targetContract(address(handler));
    }

    function invariant_V20_owner() public view {
        assertEq(
            lpm.ownerOf(tokenId),
            alice,
            "V20: NFT ownership changed"
        );
    }

    function invariant_V20_liquidity() public view {
        assertEq(
            lpm.getPositionLiquidity(tokenId),
            initialLiquidity,
            "V20: liquidity changed"
        );
    }

    function invariant_V20_noUnauthorizedApproval()
        public
        view
    {
        assertEq(
            lpm.getApproved(tokenId),
            address(0),
            "V20: unauthorized NFT approval"
        );

        assertFalse(
            lpm.isApprovedForAll(alice, bob),
            "V20: unauthorized operator approval"
        );
    }

    function invariant_V20_noUnauthorizedSuccess()
        public
        view
    {
        assertEq(
            handler.unexpectedSuccesses(),
            0,
            "V20: unauthorized operation succeeded"
        );
    }
}
