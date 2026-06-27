// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PancakeV3FeeAccountingRef} from "../src/PancakeV3FeeAccountingRef.sol";
import {TickMath} from "../src/lib/TickMath.sol";

/// @title PancakeV3TickBounds: P-2 + P-3 properties: tick + sqrtPriceX96 stay in v3 address space.
/// @notice SCOPE.md §1 P-2 + P-3. After any operation:
///         - P-2: `MIN_TICK ≤ pool.tick() ≤ MAX_TICK`
///         - P-3: `MIN_SQRT_RATIO ≤ pool.sqrtPriceX96() < MAX_SQRT_RATIO`
///
///         The bug class P-2 catches: a forked v3 pool whose swap routine
///         allows the tick to underflow / overflow without bounding to
///         MIN_TICK / MAX_TICK (e.g., a `tick += delta` without the
///         `require(tick >= MIN_TICK && tick <= MAX_TICK)` check in
///         SwapMath). The bug class P-3 catches: a fork whose
///         sqrtPriceX96 update underflows / overflows the
///         MIN_SQRT_RATIO / MAX_SQRT_RATIO bounds (e.g., a
///         `sqrtPriceX96 = nextSqrtPriceFromInput(...)` that doesn't clamp
///         to `MAX_SQRT_RATIO - 1`). Both are observed bug patterns in
///         non-canonical v3 forks.
contract PancakeV3TickBoundsTest is Test {
    PancakeV3FeeAccountingRef internal pool;

    uint24 internal constant FEE_PIPS = 500;
    uint128 internal constant INITIAL_LIQUIDITY = 1e18;
    uint160 internal constant INITIAL_SQRT_PRICE = 79228162514264337593543950336; // sqrtPrice at tick 0
    int24 internal constant INITIAL_TICK = 0;

    function setUp() public {
        pool = new PancakeV3FeeAccountingRef(FEE_PIPS, INITIAL_LIQUIDITY, INITIAL_SQRT_PRICE, INITIAL_TICK);
    }

    // ---------------------------------------------------------------------
    // P-2: tick bounds.
    // ---------------------------------------------------------------------

    function test_property_initialTick_inBounds() public view {
        int24 t = pool.tick();
        assertGe(t, TickMath.MIN_TICK);
        assertLe(t, TickMath.MAX_TICK);
    }

    function test_property_tickAtMin_admitted() public {
        // Move tick from 0 down to MIN_TICK in one step.
        pool.simulateSwapStep({
            zeroForOne: true,
            amountIn: 0,
            tickDelta: TickMath.MIN_TICK - INITIAL_TICK,
            sqrtPriceDelta: 0
        });
        assertEq(pool.tick(), TickMath.MIN_TICK);
    }

    function test_property_tickAtMax_admitted() public {
        pool.simulateSwapStep({
            zeroForOne: true,
            amountIn: 0,
            tickDelta: TickMath.MAX_TICK - INITIAL_TICK,
            sqrtPriceDelta: 0
        });
        assertEq(pool.tick(), TickMath.MAX_TICK);
    }

    function test_property_tickBelowMin_reverts() public {
        // tickDelta that would push us to MIN_TICK - 1 must revert.
        int24 delta = TickMath.MIN_TICK - INITIAL_TICK - 1;
        vm.expectRevert(bytes("tick<MIN"));
        pool.simulateSwapStep({zeroForOne: true, amountIn: 0, tickDelta: delta, sqrtPriceDelta: 0});
    }

    function test_property_tickAboveMax_reverts() public {
        int24 delta = TickMath.MAX_TICK - INITIAL_TICK + 1;
        vm.expectRevert(bytes("tick>MAX"));
        pool.simulateSwapStep({zeroForOne: true, amountIn: 0, tickDelta: delta, sqrtPriceDelta: 0});
    }

    function testFuzz_property_tickAlwaysInBounds(int24 tickDelta) public {
        // int24 already covers the full bound surface. The reference reverts
        // on out-of-bound input; surviving calls leave tick in
        // [MIN_TICK, MAX_TICK]. We swallow the revert and check the post-state.
        try pool.simulateSwapStep(true, 0, tickDelta, 0) {
            assertGe(pool.tick(), TickMath.MIN_TICK);
            assertLe(pool.tick(), TickMath.MAX_TICK);
        } catch {
            // Out-of-bound input correctly rejected; pool state unchanged.
            assertEq(pool.tick(), INITIAL_TICK);
        }
    }

    // ---------------------------------------------------------------------
    // P-3: sqrtPriceX96 bounds.
    // ---------------------------------------------------------------------

    function test_property_initialSqrtPriceX96_inBounds() public view {
        uint160 sp = pool.sqrtPriceX96();
        assertGe(sp, TickMath.MIN_SQRT_RATIO);
        assertLt(sp, TickMath.MAX_SQRT_RATIO);
    }

    function test_property_sqrtPriceAtMin_admitted() public {
        int256 delta = int256(uint256(TickMath.MIN_SQRT_RATIO)) - int256(uint256(INITIAL_SQRT_PRICE));
        pool.simulateSwapStep({zeroForOne: true, amountIn: 0, tickDelta: 0, sqrtPriceDelta: delta});
        assertEq(pool.sqrtPriceX96(), TickMath.MIN_SQRT_RATIO);
    }

    function test_property_sqrtPriceJustBelowMax_admitted() public {
        // MAX_SQRT_RATIO is the *open* upper bound; MAX-1 is the
        // largest admitted value.
        int256 delta = int256(uint256(TickMath.MAX_SQRT_RATIO) - 1) - int256(uint256(INITIAL_SQRT_PRICE));
        pool.simulateSwapStep({zeroForOne: true, amountIn: 0, tickDelta: 0, sqrtPriceDelta: delta});
        assertEq(pool.sqrtPriceX96(), TickMath.MAX_SQRT_RATIO - 1);
    }

    function test_property_sqrtPriceBelowMin_reverts() public {
        int256 delta = int256(uint256(TickMath.MIN_SQRT_RATIO)) - int256(uint256(INITIAL_SQRT_PRICE)) - 1;
        vm.expectRevert(bytes("sqrtPriceX96<MIN"));
        pool.simulateSwapStep({zeroForOne: true, amountIn: 0, tickDelta: 0, sqrtPriceDelta: delta});
    }

    function test_property_sqrtPriceAtMax_reverts() public {
        // MAX_SQRT_RATIO itself is rejected; the v3 invariant is
        // `sqrtPriceX96 < MAX_SQRT_RATIO`, strict.
        int256 delta = int256(uint256(TickMath.MAX_SQRT_RATIO)) - int256(uint256(INITIAL_SQRT_PRICE));
        vm.expectRevert(bytes("sqrtPriceX96>=MAX"));
        pool.simulateSwapStep({zeroForOne: true, amountIn: 0, tickDelta: 0, sqrtPriceDelta: delta});
    }
}
