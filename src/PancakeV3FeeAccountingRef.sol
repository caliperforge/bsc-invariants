// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {TickMath} from "./lib/TickMath.sol";

/// @title PancakeV3FeeAccountingRef: minimal v3-fee-growth + tick-bound reference.
/// @notice A same-source twin minimal to the fee-growth + tick-bound invariants
///         under test (P-1 / P-2 / P-3 per `SCOPE.md`). It is NOT a fork of
///         PancakeSwap's production v3 pool source: only the fee-accounting +
///         tick-bound state and the swap-step update rule a v3 pool uses are
///         reproduced.
///
///         The math reproduces the Uniswap v3 / PancakeSwap v3 invariant:
///         on every swap step with non-zero in-amount and non-zero fee,
///         `feeGrowthGlobalXX128` increases by `feeAmount * Q128 / liquidity`
///         (signed semantics ignored; the planted twin in M2 will swap this
///         increment for a decrement to surface the property failure).
///
///         The reference operates in "increment-only" arithmetic; we do NOT
///         wrap on overflow here. Real Uniswap v3 stores fee growth as
///         `uint256` and DOES allow wrap; the protocol's `(global - outside)`
///         subtraction recovers position-local growth under modular
///         arithmetic. Modelling that wrap is M2 work (P-5 fee-growth-outside
///         consistency); for the Week-1 invariants, increment-only is the
///         conservative reference.
contract PancakeV3FeeAccountingRef {
    /// @dev `Q128 = 2**128`, the canonical fixed-point base for v3 fee growth.
    uint256 internal constant Q128 = 0x100000000000000000000000000000000;

    // ---------------------------------------------------------------------
    // Pool state (the subset the M1 invariants exercise)
    // ---------------------------------------------------------------------

    /// @notice Current pool tick. Mirrors `Pool.slot0.tick`.
    int24 public tick;

    /// @notice Current sqrtPriceX96. Mirrors `Pool.slot0.sqrtPriceX96`.
    uint160 public sqrtPriceX96;

    /// @notice Active liquidity. Mirrors `Pool.liquidity`.
    uint128 public liquidity;

    /// @notice Cumulative fee growth per unit of liquidity, token0 side.
    ///         Mirrors `Pool.feeGrowthGlobal0X128`.
    uint256 public feeGrowthGlobal0X128;

    /// @notice Cumulative fee growth per unit of liquidity, token1 side.
    ///         Mirrors `Pool.feeGrowthGlobal1X128`.
    uint256 public feeGrowthGlobal1X128;

    /// @notice The pool fee, in units of 1e-6 of the input amount
    ///         (e.g. `500 = 0.05%`). Mirrors `Pool.fee`.
    uint24 public immutable feePips;

    // ---------------------------------------------------------------------
    // Events (for invariant traces)
    // ---------------------------------------------------------------------

    event SwapStep(
        bool zeroForOne,
        uint256 amountIn,
        uint256 feeAmount,
        int24 newTick,
        uint160 newSqrtPriceX96,
        uint256 newFeeGrowthGlobal0X128,
        uint256 newFeeGrowthGlobal1X128
    );

    // ---------------------------------------------------------------------
    // Construction
    // ---------------------------------------------------------------------

    /// @param _feePips Pool fee in 1e-6 units (e.g. 100, 500, 2500, 10000,
    ///                 the canonical PancakeSwap v3 fee tiers).
    /// @param _liquidity Initial active liquidity. Must be > 0 to admit any
    ///                   fee accrual (the v3 swap step divides by liquidity).
    /// @param _sqrtPriceX96 Initial sqrtPriceX96. Must lie in
    ///                      `[MIN_SQRT_RATIO, MAX_SQRT_RATIO)` per v3 spec.
    /// @param _tick Initial tick. Must lie in `[MIN_TICK, MAX_TICK]` per v3.
    constructor(uint24 _feePips, uint128 _liquidity, uint160 _sqrtPriceX96, int24 _tick) {
        // Guard the construction against violating the bound invariants the
        // tests assert under fuzz. Misconfigured fuzz inputs should bounce
        // here rather than admit a reference state that already violates
        // P-2 / P-3 before any operation has run.
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

    // ---------------------------------------------------------------------
    // The single mutating operation the M1 invariants exercise.
    // ---------------------------------------------------------------------

    /// @notice Simulate a single swap step. Updates fee growth on the input
    ///         side, advances the tick by `tickDelta`, and advances
    ///         sqrtPriceX96 by `sqrtPriceDelta`. Reverts if the resulting
    ///         tick or sqrtPriceX96 would exit the v3 address space; this
    ///         mirrors the upstream `require` checks in `SwapMath.sol`.
    ///
    ///         The clean reference: fee growth ALWAYS increases (or stays
    ///         flat for `amountIn = 0` / `feePips = 0`). The M2 planted twin
    ///         swaps this `+=` for a `-=` (or a no-op) to demonstrate the
    ///         property failure deterministically.
    /// @param zeroForOne If true the swap is token0->token1 and the fee
    ///                   accrues to `feeGrowthGlobal0X128`; else to
    ///                   `feeGrowthGlobal1X128`.
    /// @param amountIn The gross input amount (pre-fee). The fee amount is
    ///                 `amountIn * feePips / 1_000_000`.
    /// @param tickDelta Signed tick movement. The post-step tick must lie in
    ///                  `[MIN_TICK, MAX_TICK]`.
    /// @param sqrtPriceDelta Signed sqrtPriceX96 movement. The post-step
    ///                       sqrtPriceX96 must lie in
    ///                       `[MIN_SQRT_RATIO, MAX_SQRT_RATIO)`.
    function simulateSwapStep(
        bool zeroForOne,
        uint256 amountIn,
        int24 tickDelta,
        int256 sqrtPriceDelta
    ) external {
        // Tick + sqrtPriceX96 bounds (P-2 + P-3). We require the post-step
        // values to lie in bounds; the v3 upstream enforces this in
        // SwapMath.computeSwapStep + Pool._modifyPosition.
        int256 newTickSigned = int256(tick) + int256(tickDelta);
        require(newTickSigned >= int256(TickMath.MIN_TICK), "tick<MIN");
        require(newTickSigned <= int256(TickMath.MAX_TICK), "tick>MAX");

        int256 newSqrtSigned = int256(uint256(sqrtPriceX96)) + sqrtPriceDelta;
        require(newSqrtSigned >= int256(uint256(TickMath.MIN_SQRT_RATIO)), "sqrtPriceX96<MIN");
        require(newSqrtSigned < int256(uint256(TickMath.MAX_SQRT_RATIO)), "sqrtPriceX96>=MAX");

        // Fee growth (P-1). The increment is `feeAmount * Q128 / liquidity`.
        // We cap `amountIn` at type(uint128).max to keep `feeAmount * Q128`
        // safely inside uint256; v3's actual cap is implicit in pool reserves.
        uint256 capped = amountIn > type(uint128).max ? type(uint128).max : amountIn;
        uint256 feeAmount = (capped * uint256(feePips)) / 1_000_000;

        if (feeAmount > 0) {
            // `liquidity > 0` is guaranteed by the constructor + (M2) by the
            // mint/burn invariants. mulDiv-free path is sufficient for the
            // bounded `capped`.
            uint256 deltaX128 = (feeAmount * Q128) / uint256(liquidity);
            if (zeroForOne) {
                feeGrowthGlobal0X128 += deltaX128;
            } else {
                feeGrowthGlobal1X128 += deltaX128;
            }
        }

        // forge-lint: disable-next-line(unsafe-typecast) // safe: the require checks above pin newTickSigned to [MIN_TICK, MAX_TICK], which fits int24.
        tick = int24(newTickSigned);
        // forge-lint: disable-next-line(unsafe-typecast) // safe: the require checks above pin newSqrtSigned to [MIN_SQRT_RATIO, MAX_SQRT_RATIO), which is non-negative and fits uint160.
        sqrtPriceX96 = uint160(uint256(newSqrtSigned));

        emit SwapStep(
            zeroForOne,
            capped,
            feeAmount,
            tick,
            sqrtPriceX96,
            feeGrowthGlobal0X128,
            feeGrowthGlobal1X128
        );
    }
}
