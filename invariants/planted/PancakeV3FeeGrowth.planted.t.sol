// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {TickMath} from "../../src/lib/TickMath.sol";

/// @title PancakeV3FeeGrowth (planted): P-1 planted twin: assignment-instead-of-accumulation
///        breaks fee-growth monotonicity and fires
///        `INVARIANT VIOLATED feeGrowth_neverDecreases`.
///
/// @notice SCOPE.md §1 P-1 (planted leg). Counterpart twin to
///         `invariants/PancakeV3FeeGrowth.t.sol` (the clean leg). The single
///         localized change is in `BrokenPancakeV3FeeAccountingRef.simulateSwapStep`:
///         the canonical Uniswap v3 / PancakeSwap v3 update
///
///             feeGrowthGlobal0X128 += deltaX128;
///
///         is mis-ported as
///
///             feeGrowthGlobal0X128 = deltaX128;
///
///         on the zeroForOne branch. This is a documented bug class: a forked
///         v3 pool whose dev hand-translated the swap loop and dropped the
///         accumulator semantic, treating each swap-step's fee delta as the
///         new fee growth rather than an addend (see docs/invariants.md P-1
///         "Bug class caught"). A sequence of zeroForOne swaps with
///         monotonically decreasing in-amount produces a strictly decreasing
///         feeGrowthGlobal0X128 after the first step.
///
/// @dev CI spec (ci.yml `p1-feegrowth-planted-fires`): planted leg exits
///      non-zero with at least one `INVARIANT VIOLATED feeGrowth_neverDecreases`
///      line on stdout. Twin diff vs clean reference: ONE localized hunk
///      (the `+=` → `=` swap on the zeroForOne fee0 path).

// ---------------------------------------------------------------------------
// Planted reference: same interface + storage as src/PancakeV3FeeAccountingRef,
// with the single planted hunk inline. Lives in the test file (NOT in src/)
// because it is a documented bug-class model rather than a production
// reference. Mirrors the hyperevm-safety planted convention.
// ---------------------------------------------------------------------------

contract BrokenPancakeV3FeeAccountingRef {
    uint256 internal constant Q128 = 0x100000000000000000000000000000000;

    int24 public tick;
    uint160 public sqrtPriceX96;
    uint128 public liquidity;
    uint256 public feeGrowthGlobal0X128;
    uint256 public feeGrowthGlobal1X128;
    uint24 public immutable feePips;

    constructor(uint24 _feePips, uint128 _liquidity, uint160 _sqrtPriceX96, int24 _tick) {
        require(_liquidity > 0, "liquidity=0");
        require(_sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO, "sqrtPriceX96<MIN");
        require(_sqrtPriceX96 < TickMath.MAX_SQRT_RATIO, "sqrtPriceX96>=MAX");
        require(_tick >= TickMath.MIN_TICK, "tick<MIN");
        require(_tick <= TickMath.MAX_TICK, "tick>MAX");

        feePips = _feePips;
        liquidity = _liquidity;
        sqrtPriceX96 = _sqrtPriceX96;
        tick = _tick;
    }

    /// @dev PLANTED: the `feeGrowthGlobal0X128 = deltaX128` assignment on the
    ///      zeroForOne branch. The clean reference uses `+=`. The token1
    ///      branch is left correct so the bug is localized to one accumulator.
    function simulateSwapStep(
        bool zeroForOne,
        uint256 amountIn,
        int24 tickDelta,
        int256 sqrtPriceDelta
    ) external {
        int256 newTickSigned = int256(tick) + int256(tickDelta);
        require(newTickSigned >= int256(TickMath.MIN_TICK), "tick<MIN");
        require(newTickSigned <= int256(TickMath.MAX_TICK), "tick>MAX");

        int256 newSqrtSigned = int256(uint256(sqrtPriceX96)) + sqrtPriceDelta;
        require(newSqrtSigned >= int256(uint256(TickMath.MIN_SQRT_RATIO)), "sqrtPriceX96<MIN");
        require(newSqrtSigned < int256(uint256(TickMath.MAX_SQRT_RATIO)), "sqrtPriceX96>=MAX");

        uint256 capped = amountIn > type(uint128).max ? type(uint128).max : amountIn;
        uint256 feeAmount = (capped * uint256(feePips)) / 1_000_000;

        if (feeAmount > 0) {
            uint256 deltaX128 = (feeAmount * Q128) / uint256(liquidity);
            if (zeroForOne) {
                // BUG: assignment, not accumulation. Each zeroForOne swap
                // overwrites prior fee0 growth with just this step's delta.
                feeGrowthGlobal0X128 = deltaX128;
            } else {
                feeGrowthGlobal1X128 += deltaX128;
            }
        }

        // forge-lint: disable-next-line(unsafe-typecast) // safe: the require checks above pin newTickSigned to [MIN_TICK, MAX_TICK], which fits int24.
        tick = int24(newTickSigned);
        // forge-lint: disable-next-line(unsafe-typecast) // safe: the require checks above pin newSqrtSigned to [MIN_SQRT_RATIO, MAX_SQRT_RATIO), which is non-negative and fits uint160.
        sqrtPriceX96 = uint160(uint256(newSqrtSigned));
    }
}

// ---------------------------------------------------------------------------
// Planted test: the property fires deterministically. Two witnesses: a
// fixed-input boundary test and a fuzz sweep over the decreasing-amount
// surface.
// ---------------------------------------------------------------------------

contract PancakeV3FeeGrowthPlantedTest is Test {
    BrokenPancakeV3FeeAccountingRef internal broken;

    uint24 internal constant FEE_PIPS = 500;
    uint128 internal constant INITIAL_LIQUIDITY = 1e18;
    uint160 internal constant INITIAL_SQRT_PRICE = 79228162514264337593543950336; // sqrtPrice at tick 0
    int24 internal constant INITIAL_TICK = 0;

    function setUp() public {
        broken = new BrokenPancakeV3FeeAccountingRef(
            FEE_PIPS, INITIAL_LIQUIDITY, INITIAL_SQRT_PRICE, INITIAL_TICK
        );
    }

    /// @notice Deterministic witness. First swap with a large amountIn seeds
    ///         `feeGrowthGlobal0X128` to a large value; a second swap with a
    ///         smaller amountIn overwrites it (instead of accumulating),
    ///         producing a strict decrease: the property failure.
    function test_property_planted_zeroForOne_decreasingAmount_invariantViolated() public {
        uint256 amount1 = 1e24;
        uint256 amount2 = 1e22;

        broken.simulateSwapStep({zeroForOne: true, amountIn: amount1, tickDelta: 0, sqrtPriceDelta: 0});
        uint256 after1 = broken.feeGrowthGlobal0X128();

        broken.simulateSwapStep({zeroForOne: true, amountIn: amount2, tickDelta: 0, sqrtPriceDelta: 0});
        uint256 after2 = broken.feeGrowthGlobal0X128();

        if (after2 < after1) {
            console2.log("INVARIANT VIOLATED feeGrowth_neverDecreases (token0)");
            console2.log("  amount1                =", amount1);
            console2.log("  feeGrowthGlobal0X128_1 =", after1);
            console2.log("  amount2                =", amount2);
            console2.log("  feeGrowthGlobal0X128_2 =", after2);
            console2.log("  (planted bug: `=` instead of `+=` on the zeroForOne fee0 path)");
            revert("INVARIANT VIOLATED feeGrowth_neverDecreases");
        }
    }

    /// @notice Fuzz: any pair (amount1, amount2) with amount1 > amount2 ≥ 2000
    ///         produces a strictly decreasing feeGrowthGlobal0X128: the
    ///         planted bug magnifies the gap by feePips × Q128 / liquidity,
    ///         so the property always fires.
    function testFuzz_property_planted_zeroForOne_decreasingAmount_invariantViolated(
        uint128 a1,
        uint128 a2
    ) public {
        // Bound a1 strictly above a2 so the second-step delta is strictly
        // smaller than the first. Lower bound 2000 keeps `feeAmount > 0` at
        // FEE_PIPS = 500. Upper bound type(uint128).max - 1 keeps room for a1.
        uint256 amount2 = uint256(a2);
        if (amount2 < 2000) amount2 = 2000;
        if (amount2 > type(uint128).max - 1) amount2 = type(uint128).max - 1;
        uint256 amount1 = uint256(a1);
        if (amount1 <= amount2) amount1 = amount2 + 1;
        if (amount1 > type(uint128).max) amount1 = type(uint128).max;

        broken.simulateSwapStep({zeroForOne: true, amountIn: amount1, tickDelta: 0, sqrtPriceDelta: 0});
        uint256 after1 = broken.feeGrowthGlobal0X128();

        broken.simulateSwapStep({zeroForOne: true, amountIn: amount2, tickDelta: 0, sqrtPriceDelta: 0});
        uint256 after2 = broken.feeGrowthGlobal0X128();

        if (after2 < after1) {
            console2.log("INVARIANT VIOLATED feeGrowth_neverDecreases (token0)");
            console2.log("  amount1                =", amount1);
            console2.log("  feeGrowthGlobal0X128_1 =", after1);
            console2.log("  amount2                =", amount2);
            console2.log("  feeGrowthGlobal0X128_2 =", after2);
            revert("INVARIANT VIOLATED feeGrowth_neverDecreases");
        }
    }
}
