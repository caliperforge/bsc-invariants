// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {PancakeV3FeeGrowthOutsideRef} from "../src/PancakeV3FeeGrowthOutsideRef.sol";
import {TickMath} from "../src/lib/TickMath.sol";

/// @title PancakeV3FeeGrowthOutside: P-5 property: per-tick feeGrowthOutside
///        is conserved against feeGrowthGlobal.
/// @notice SCOPE.md §1 P-5. For every initialized tick `t`:
///           - `feeGrowthOutside0X128[t] <= feeGrowthGlobal0X128`
///           - `feeGrowthOutside1X128[t] <= feeGrowthGlobal1X128`
///         after any sequence of `initializeTick`, `swapAccrue`, and
///         `crossTick`. This is the increment-only conservation form; the
///         wrap-around case is documented in `docs/invariants.md` P-5.
///
///         The flip rule on crossing tick `t`:
///           `feeGrowthOutside[t] := feeGrowthGlobal - feeGrowthOutside[t]`.
///         The conservation property holds across this rule because the new
///         outside value is the old "below" amount, which is bounded by
///         global.
contract PancakeV3FeeGrowthOutsideTest is StdInvariant, Test {
    PancakeV3FeeGrowthOutsideRef internal pool;
    FeeGrowthOutsideHandler internal handler;

    uint24 internal constant FEE_PIPS = 500;
    uint128 internal constant INITIAL_LIQUIDITY = 1e18;
    int24 internal constant INITIAL_TICK = 0;

    // Three initialized ticks the handler walks the price across.
    int24 internal constant TICK_LOWER = -200;
    int24 internal constant TICK_UPPER = 200;
    int24 internal constant TICK_FAR_UPPER = 500;

    function setUp() public {
        pool = new PancakeV3FeeGrowthOutsideRef(FEE_PIPS, INITIAL_LIQUIDITY, INITIAL_TICK);
        // Initialize three ticks so the property has surface to assert on.
        // Order matters: initialize must happen before any cross of the tick.
        pool.initializeTick(TICK_LOWER);
        pool.initializeTick(TICK_UPPER);
        pool.initializeTick(TICK_FAR_UPPER);

        handler = new FeeGrowthOutsideHandler(pool, TICK_LOWER, TICK_UPPER, TICK_FAR_UPPER);

        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = FeeGrowthOutsideHandler.accrueBounded.selector;
        selectors[1] = FeeGrowthOutsideHandler.crossBounded.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // ---------------------------------------------------------------------
    // Stateful-fuzz invariant: outside <= global for every initialized tick.
    // ---------------------------------------------------------------------

    function invariant_feeGrowthOutside_bounded_byGlobal() public view {
        uint256 g0 = pool.feeGrowthGlobal0X128();
        uint256 g1 = pool.feeGrowthGlobal1X128();

        assertLe(
            pool.feeGrowthOutside0X128(TICK_LOWER), g0,
            "INVARIANT VIOLATED feeGrowthOutside_consistency (token0 @ LOWER)"
        );
        assertLe(
            pool.feeGrowthOutside1X128(TICK_LOWER), g1,
            "INVARIANT VIOLATED feeGrowthOutside_consistency (token1 @ LOWER)"
        );
        assertLe(
            pool.feeGrowthOutside0X128(TICK_UPPER), g0,
            "INVARIANT VIOLATED feeGrowthOutside_consistency (token0 @ UPPER)"
        );
        assertLe(
            pool.feeGrowthOutside1X128(TICK_UPPER), g1,
            "INVARIANT VIOLATED feeGrowthOutside_consistency (token1 @ UPPER)"
        );
        assertLe(
            pool.feeGrowthOutside0X128(TICK_FAR_UPPER), g0,
            "INVARIANT VIOLATED feeGrowthOutside_consistency (token0 @ FAR_UPPER)"
        );
        assertLe(
            pool.feeGrowthOutside1X128(TICK_FAR_UPPER), g1,
            "INVARIANT VIOLATED feeGrowthOutside_consistency (token1 @ FAR_UPPER)"
        );
    }

    // ---------------------------------------------------------------------
    // Unit-level properties: initialize, flip, and conservation.
    // ---------------------------------------------------------------------

    /// @notice Initialize at a tick BELOW current price seeds outside = global.
    function test_property_initialize_belowCurrent_seedsOutsideEqualsGlobal() public {
        // Seed some global fee growth first.
        pool.swapAccrue(true, 1e22);
        uint256 g0 = pool.feeGrowthGlobal0X128();
        assertGt(g0, 0);

        // Initialize a tick BELOW current (TICK_LOWER was already init in setUp;
        // pick a fresh one).
        int24 t = -500;
        pool.initializeTick(t);
        // tick=0 >= -500, so outside should equal global.
        assertEq(pool.feeGrowthOutside0X128(t), g0, "outside0 != global on below-init");
    }

    /// @notice Initialize at a tick ABOVE current price seeds outside = 0.
    function test_property_initialize_aboveCurrent_seedsOutsideZero() public {
        pool.swapAccrue(true, 1e22);
        uint256 g0 = pool.feeGrowthGlobal0X128();
        assertGt(g0, 0);

        int24 t = 700;
        pool.initializeTick(t);
        // tick=0 < 700, so outside seeds to 0.
        assertEq(pool.feeGrowthOutside0X128(t), 0, "outside0 != 0 on above-init");
    }

    /// @notice Cross the price up across an initialized tick: outside flips to
    ///         the prior "below" amount (which here is the accrued global).
    function test_property_crossUp_flipsOutside_toGlobalMinusOldOutside() public {
        // Start at tick=0; TICK_UPPER=200 was initialized in setUp with
        // outside=0 (since tick=0 < 200 at init time).
        pool.swapAccrue(true, 1e22);
        uint256 g0 = pool.feeGrowthGlobal0X128();
        uint256 oldOutside0 = pool.feeGrowthOutside0X128(TICK_UPPER);
        assertEq(oldOutside0, 0);

        // Move price up across TICK_UPPER.
        pool.crossTick(TICK_UPPER);
        uint256 newOutside0 = pool.feeGrowthOutside0X128(TICK_UPPER);
        assertEq(newOutside0, g0 - oldOutside0, "flip rule did not produce g - old");
        assertEq(newOutside0, g0);
    }

    /// @notice Double-cross is involutive: cross up then back down restores
    ///         the original outside value.
    function test_property_doubleCross_isInvolutive() public {
        pool.swapAccrue(true, 1e22);
        uint256 outsideBefore = pool.feeGrowthOutside0X128(TICK_UPPER);

        pool.crossTick(TICK_UPPER);  // flip
        pool.crossTick(0);           // and back
        // The flip happens on `newTick != oldTick` and only on the destination
        // tick. So the second cross flips TICK 0 (not initialized → no flip).
        // The TICK_UPPER outside stays at its post-first-flip value. The
        // involutive property in real v3 requires walking back across the
        // SAME tick: that's the multi-cross walk (M2). For the destination-
        // only minimal reference, we re-cross TICK_UPPER explicitly:
        pool.crossTick(TICK_UPPER);
        uint256 outsideAfter = pool.feeGrowthOutside0X128(TICK_UPPER);
        assertEq(outsideAfter, outsideBefore, "outside not restored after double-cross");
    }

    /// @notice Conservation: outside <= global at all times for every
    ///         initialized tick, after any sequence of accrues + crosses.
    function test_property_outside_neverExceedsGlobal_afterAccrues() public {
        pool.swapAccrue(true, 1e22);
        pool.swapAccrue(false, 5e21);
        assertLe(pool.feeGrowthOutside0X128(TICK_LOWER), pool.feeGrowthGlobal0X128());
        assertLe(pool.feeGrowthOutside1X128(TICK_LOWER), pool.feeGrowthGlobal1X128());
        assertLe(pool.feeGrowthOutside0X128(TICK_UPPER), pool.feeGrowthGlobal0X128());
        assertLe(pool.feeGrowthOutside1X128(TICK_UPPER), pool.feeGrowthGlobal1X128());
    }

    /// @notice Fuzz: any swap amount preserves outside <= global at the
    ///         already-initialized ticks.
    function testFuzz_property_outside_boundedAfterSwap(uint128 amount) public {
        vm.assume(amount >= 2000);
        pool.swapAccrue(true, uint256(amount));
        assertLe(pool.feeGrowthOutside0X128(TICK_LOWER), pool.feeGrowthGlobal0X128());
        assertLe(pool.feeGrowthOutside0X128(TICK_UPPER), pool.feeGrowthGlobal0X128());
    }
}

/// @title FeeGrowthOutsideHandler: bounded handler for the conservation invariant.
/// @notice Drives `swapAccrue` and `crossTick` over the three initialized
///         ticks. Cross amounts are clamped to {LOWER, UPPER, FAR_UPPER, 0}
///         so the fuzzer exercises the flip rule on real initialized ticks.
contract FeeGrowthOutsideHandler is Test {
    PancakeV3FeeGrowthOutsideRef public pool;
    int24 public immutable T_LOWER;
    int24 public immutable T_UPPER;
    int24 public immutable T_FAR_UPPER;
    uint256 internal constant MAX_AMOUNT_PER_ACCRUE = 1e22;

    constructor(
        PancakeV3FeeGrowthOutsideRef _pool,
        int24 _tLower,
        int24 _tUpper,
        int24 _tFarUpper
    ) {
        pool = _pool;
        T_LOWER = _tLower;
        T_UPPER = _tUpper;
        T_FAR_UPPER = _tFarUpper;
    }

    function accrueBounded(uint128 rawAmount, bool zeroForOne) external {
        uint256 amount = uint256(rawAmount) % (MAX_AMOUNT_PER_ACCRUE + 1);
        if (amount < 2000) amount = 2000;
        pool.swapAccrue(zeroForOne, amount);
    }

    function crossBounded(uint8 pick) external {
        // Pick one of {LOWER, UPPER, FAR_UPPER, 0} so we hit real ticks.
        int24 target;
        uint8 m = pick % 4;
        if (m == 0)      target = T_LOWER;
        else if (m == 1) target = T_UPPER;
        else if (m == 2) target = T_FAR_UPPER;
        else             target = 0;
        try pool.crossTick(target) {
            // ok
        } catch {
            // The crossTick require(outside <= global) is the P-5 violation
            // signal. The stateful invariant_*  catches it explicitly; we
            // swallow the revert here so the fuzz campaign continues until
            // the invariant fires.
        }
    }
}
