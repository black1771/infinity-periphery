// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {Currency} from "infinity-core/src/types/Currency.sol";
import {IHooks} from "infinity-core/src/interfaces/IHooks.sol";
import {PoolId} from "infinity-core/src/types/PoolId.sol";
import {PoolKey} from "infinity-core/src/types/PoolKey.sol";
import {ICLPoolManager} from "infinity-core/src/pool-cl/interfaces/ICLPoolManager.sol";
import {IVault} from "infinity-core/src/interfaces/IVault.sol";

import {PosmTestSetup} from "../shared/PosmTestSetup.sol";
import {Actions} from "../../../src/libraries/Actions.sol";
import {Planner, Plan} from "../../../src/libraries/Planner.sol";
import {ActionConstants} from "../../../src/libraries/ActionConstants.sol";
import {CLPositionManager} from "../../../src/pool-cl/CLPositionManager.sol";

contract ByblackHandlerV18 is Test {
    CLPositionManager public manager;
    address public alice;
    address public bob;
    uint256 public tokenId;
    uint256 public initialLiquidity;

    uint256 public attempts;
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
        initialLiquidity = manager.getPositionLiquidity(tokenId);
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

        attempts++;

        vm.prank(bob);

        try manager.modifyLiquidities(
            plan.encode(),
            block.timestamp + 100
        ) {
            unexpectedSuccesses++;
        } catch {}
    }
}

contract ByblackInvariantV18 is
    PosmTestSetup,
    StdInvariant
{
    ByblackHandlerV18 public handler;

    address alice = makeAddr("V18_ALICE");
    address bob = makeAddr("V18_BOB");

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

        handler = new ByblackHandlerV18(
            CLPositionManager(address(lpm)),
            alice,
            bob,
            tokenId
        );

        targetContract(address(handler));
    }

    function invariant_byblack_V18_ownership() public view {
        assertEq(
            lpm.ownerOf(tokenId),
            alice,
            "V18 ownership changed"
        );
    }

    function invariant_byblack_V18_liquidity() public view {
        assertEq(
            lpm.getPositionLiquidity(tokenId),
            initialLiquidity,
            "V18 liquidity changed"
        );
    }

    function invariant_byblack_V18_noUnauthorizedSuccess()
        public
        view
    {
        assertEq(
            handler.unexpectedSuccesses(),
            0,
            "V18 unauthorized operation succeeded"
        );
    }
}
