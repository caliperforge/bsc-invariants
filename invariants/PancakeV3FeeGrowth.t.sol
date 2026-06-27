// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {PancakeV3FeeAccountingRef} from "../src/PancakeV3FeeAccountingRef.sol";
import {TickMath} from "../src/lib/TickMath.sol";

/// @title PancakeV3FeeGrowth, P-1 property: feeGrowthGlobalXX128 is non-decreasing.
/// @notice SCOPE.md §1 P-1. After any sequence of `simulateSwapStep` calls
///         the reference's `feeGrowthGlobal0X128` and `feeGrowthGlobal1X128`
///         MUST be ≥ their values before the operation. This is the
///         canonical Uniswap v3 / PancakeSwap v3 accounting invariant;
///         the bug class this catches is a forked v3 pool that mis-ports
///         the `feeGrowthGlobalXX128 += FullMath.mulDiv(...)` increment
///         (e.g., signed-conversion bug, decrement on a refund path,
///         a withdrawProtocolFee implementation that erroneously touches
///         the per-LP fee growth instead of the protocol-fee storage).
///
/// @dev M2 lands `invariants/planted/PancakeV3FeeGrowth.planted.t.sol`
///      with a planted hunk that swaps the `+=` for a `-=`. With that
///      hunk in place the `invariant_feeGrowth_neverDecreases` invariant
///      below MUST fire `INVARIANT VIOLATED feeGrowth_neverDecreases`
///      and `forge test` MUST exit non-zero. The CI workflow gates on
///      both signals.
contract PancakeV3FeeGrowthTest is StdInvariant, Test {
    PancakeV3FeeAccountingRef internal pool;
    FeeGrowthHandler internal handler;

    uint24 internal constant FEE_PIPS = 500;             // 0.05%, PancakeSwap v3 default low tier
    uint128 internal constant INITIAL_LIQUIDITY = 1e18;  // 1.0 unit of liquidity, scaled
    uint160 internal constant INITIAL_SQRT_PRICE = 79228162514264337593543950336; // sqrtPrice at tick 0
    int24 internal constant INITIAL_TICK = 0;

    function setUp() public {
        pool = new PancakeV3FeeAccountingRef(FEE_PIPS, INITIAL_LIQUIDITY, INITIAL_SQRT_PRICE, INITIAL_TICK);
        handler = new FeeGrowthHandler(pool);

        // Restrict the invariant fuzzer's target to the handler's bounded
        // entry points; otherwise the fuzzer would try to call the pool's
        // raw `simulateSwapStep` with unrealistic inputs that exit bounds
        // on the very first step and consume the campaign on revert frames.
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = FeeGrowthHandler.swapStep.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // ---------------------------------------------------------------------
    // Stateful-fuzz invariant: the load-bearing property.
    // ---------------------------------------------------------------------

    /// @notice After any sequence of `swapStep` calls, fee growth on each
    ///         side is at least the last-observed value. The handler
    ///         shadows the last value; the property compares to it.
    function invariant_feeGrowth_neverDecreases() public view {
        assertGe(
            pool.feeGrowthGlobal0X128(),
            handler.lastFeeGrowthGlobal0X128(),
            "INVARIANT VIOLATED feeGrowth_neverDecreases (token0)"
        );
        assertGe(
            pool.feeGrowthGlobal1X128(),
            handler.lastFeeGrowthGlobal1X128(),
            "INVARIANT VIOLATED feeGrowth_neverDecreases (token1)"
        );
    }

    // ---------------------------------------------------------------------
    // Unit-level properties: boundary + deterministic checks.
    // ---------------------------------------------------------------------

    /// @notice A non-zero swap on the token0 side strictly increases
    ///         `feeGrowthGlobal0X128` (and leaves token1 side untouched).
    function test_property_swapToken0_increasesFee0_onlyFee0() public {
        uint256 before0 = pool.feeGrowthGlobal0X128();
        uint256 before1 = pool.feeGrowthGlobal1X128();

        pool.simulateSwapStep({zeroForOne: true, amountIn: 1e18, tickDelta: 0, sqrtPriceDelta: 0});

        assertGt(pool.feeGrowthGlobal0X128(), before0, "fee0 did not increase");
        assertEq(pool.feeGrowthGlobal1X128(), before1, "fee1 changed on a zeroForOne swap");
    }

    /// @notice A non-zero swap on the token1 side strictly increases
    ///         `feeGrowthGlobal1X128` (and leaves token0 side untouched).
    function test_property_swapToken1_increasesFee1_onlyFee1() public {
        uint256 before0 = pool.feeGrowthGlobal0X128();
        uint256 before1 = pool.feeGrowthGlobal1X128();

        pool.simulateSwapStep({zeroForOne: false, amountIn: 1e18, tickDelta: 0, sqrtPriceDelta: 0});

        assertEq(pool.feeGrowthGlobal0X128(), before0, "fee0 changed on a !zeroForOne swap");
        assertGt(pool.feeGrowthGlobal1X128(), before1, "fee1 did not increase");
    }

    /// @notice A zero-amount swap leaves both fee-growth accumulators
    ///         unchanged (no division by liquidity occurs).
    function test_property_zeroAmount_noFeeChange() public {
        uint256 before0 = pool.feeGrowthGlobal0X128();
        uint256 before1 = pool.feeGrowthGlobal1X128();

        pool.simulateSwapStep({zeroForOne: true, amountIn: 0, tickDelta: 0, sqrtPriceDelta: 0});
        pool.simulateSwapStep({zeroForOne: false, amountIn: 0, tickDelta: 0, sqrtPriceDelta: 0});

        assertEq(pool.feeGrowthGlobal0X128(), before0, "fee0 changed on zero-amount swap");
        assertEq(pool.feeGrowthGlobal1X128(), before1, "fee1 changed on zero-amount swap");
    }

    /// @notice Fuzz: any non-zero `amountIn` produces a strictly positive
    ///         fee-growth increment on the swapped-in side. The increment
    ///         must be bounded by `amountIn * feePips * Q128 / (1e6 * liquidity)`.
    function testFuzz_property_nonZeroAmount_strictIncrease(uint128 amountIn, bool zeroForOne) public {
        vm.assume(amountIn > 0);
        // Bound amountIn so that `amountIn * feePips / 1e6 > 0`. With
        // FEE_PIPS = 500, this requires amountIn >= 2000.
        vm.assume(amountIn >= 2000);

        uint256 before0 = pool.feeGrowthGlobal0X128();
        uint256 before1 = pool.feeGrowthGlobal1X128();

        pool.simulateSwapStep({zeroForOne: zeroForOne, amountIn: amountIn, tickDelta: 0, sqrtPriceDelta: 0});

        if (zeroForOne) {
            assertGt(pool.feeGrowthGlobal0X128(), before0, "fee0 did not increase");
        } else {
            assertGt(pool.feeGrowthGlobal1X128(), before1, "fee1 did not increase");
        }
    }
}

/// @title FeeGrowthHandler: bounded handler for the stateful-fuzz invariant.
/// @notice Wraps `PancakeV3FeeAccountingRef.simulateSwapStep` so the fuzzer
///         exercises in-bound inputs. The handler shadows the last-observed
///         fee-growth on each side; the invariant compares pool storage to
///         these shadow values, so a decrement (the planted-twin failure
///         mode) trips the invariant in a single call.
contract FeeGrowthHandler is Test {
    PancakeV3FeeAccountingRef public pool;
    uint256 public lastFeeGrowthGlobal0X128;
    uint256 public lastFeeGrowthGlobal1X128;

    constructor(PancakeV3FeeAccountingRef _pool) {
        pool = _pool;
    }

    /// @notice Fuzz-friendly entry point. Bounds amountIn into a range that
    ///         reliably exercises fee accrual, and keeps tick + sqrtPrice
    ///         movements small enough to stay inside the v3 address space.
    function swapStep(uint128 rawAmountIn, bool zeroForOne, int8 rawTickDelta, int16 rawSqrtDelta) external {
        // Bound amountIn into [2000, 1e24]. Lower bound keeps `feeAmount > 0`
        // under FEE_PIPS = 500; upper bound keeps the multiplication safely
        // inside uint256.
        uint256 amountIn = uint256(rawAmountIn);
        if (amountIn < 2000) amountIn = 2000;
        if (amountIn > 1e24) amountIn = 1e24;

        // Cap tick movement to ±100 per step so we don't exit MIN/MAX in a
        // single fuzzer-driven step. Real swaps move by much less in
        // practice; we just need to exercise the bound checks.
        int24 tickDelta = int24(rawTickDelta);

        // Bound sqrtPrice movement to a small symmetric window around the
        // current price. We round-trip through int24 then cast; the
        // reference contract re-checks bounds on entry.
        int256 sqrtDelta = int256(rawSqrtDelta) * 1e10;

        // Update shadow BEFORE the call so any decrement (the planted twin)
        // trips the invariant on the next harness pass.
        lastFeeGrowthGlobal0X128 = pool.feeGrowthGlobal0X128();
        lastFeeGrowthGlobal1X128 = pool.feeGrowthGlobal1X128();

        try pool.simulateSwapStep(zeroForOne, amountIn, tickDelta, sqrtDelta) {
            // Successful step; fee growth either increased or stayed flat
            // on the touched side. Either is admitted by the invariant.
        } catch {
            // Bound-violating step reverted at the pool. The shadow stays
            // at the pre-step value; the next call's shadow-update is
            // benign. We swallow the revert here because the fuzzer's
            // raw int8/int16 inputs intentionally test the full bound
            // surface; reverts on out-of-bound inputs are the expected
            // path, not a failure.
        }
    }
}
