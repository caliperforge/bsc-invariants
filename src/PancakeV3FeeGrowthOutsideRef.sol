// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {TickMath} from "./lib/TickMath.sol";

/// @title PancakeV3FeeGrowthOutsideRef — minimal v3 per-tick feeGrowthOutside reference.
/// @notice A same-source twin minimal to the P-5 FeeGrowthOutsideConsistency
///         invariant (SCOPE.md §1 P-5). Models the per-tick
///         `feeGrowthOutside0/1X128` state and the canonical Uniswap v3 /
///         PancakeSwap v3 update rules:
///
///         1. On tick initialization: if `currentTick >= t`,
///            `feeGrowthOutside[t] = feeGrowthGlobal`; else `feeGrowthOutside[t] = 0`.
///            (See `Tick.update` in Uniswap v3 — the
///            `tickCurrent >= tick` branch.)
///
///         2. On tick cross: `feeGrowthOutside[t] = feeGrowthGlobal - feeGrowthOutside[t]`.
///            (See `Tick.cross` in Uniswap v3.)
///
///         The conservation invariant P-5 asserts: at all times, for every
///         initialized tick `t`, `feeGrowthOutside[t] <= feeGrowthGlobal`.
///         This is the increment-only conservation form; real v3 admits
///         wrap-around on `feeGrowthGlobal` and the `(global - outside)`
///         subtraction recovers position-local growth modulo 2^256. Modelling
///         the wrap is documented in `docs/invariants.md` P-5 — for the M1
///         + M2 ranges of swap amounts the increment-only reference is
///         strictly conservative.
///
///         Bug class caught: a forked v3 pool whose `Tick.cross` flip
///         direction is wrong, whose `Tick.update` initializes outside on
///         the wrong branch, or whose fee accrual fails to maintain
///         `outside <= global`.
contract PancakeV3FeeGrowthOutsideRef {
    /// @dev `Q128 = 2**128`, the canonical fixed-point base for v3 fee growth.
    uint256 internal constant Q128 = 0x100000000000000000000000000000000;

    // ---------------------------------------------------------------------
    // Pool state
    // ---------------------------------------------------------------------

    int24 public tick;
    uint128 public liquidity;
    uint256 public feeGrowthGlobal0X128;
    uint256 public feeGrowthGlobal1X128;
    uint24 public immutable feePips;

    // ---------------------------------------------------------------------
    // Per-tick state (the P-5 surface)
    // ---------------------------------------------------------------------

    /// @notice Whether a tick has been initialized (mint touched it).
    mapping(int24 => bool) public tickInitialized;

    /// @notice Per-tick fee growth on the OPPOSITE side of `tick` from the
    ///         current price. The exact semantics follow Uniswap v3:
    ///         `feeGrowthOutside[t]` is interpreted as "fees accrued while
    ///         the price was on the side of `t` that does NOT include the
    ///         pool's current tick".
    mapping(int24 => uint256) public feeGrowthOutside0X128;
    mapping(int24 => uint256) public feeGrowthOutside1X128;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event TickInitialized(int24 indexed tick, uint256 feeGrowthOutside0X128, uint256 feeGrowthOutside1X128);
    event TickCrossed(int24 indexed oldTick, int24 indexed newTick, int24 indexed crossedTick);
    event SwapAccrue(bool zeroForOne, uint256 feeAmount, uint256 deltaX128);

    // ---------------------------------------------------------------------
    // Construction
    // ---------------------------------------------------------------------

    constructor(uint24 _feePips, uint128 _liquidity, int24 _tick) {
        require(_liquidity > 0, "liquidity=0");
        require(_tick >= TickMath.MIN_TICK, "tick<MIN");
        require(_tick <= TickMath.MAX_TICK, "tick>MAX");
        feePips = _feePips;
        liquidity = _liquidity;
        tick = _tick;
    }

    // ---------------------------------------------------------------------
    // Mutating surface
    // ---------------------------------------------------------------------

    /// @notice Initialize a tick. If the pool's current price is at or above
    ///         `t`, `feeGrowthOutside[t]` is seeded to the current global
    ///         (per Uniswap v3 `Tick.update` convention). Otherwise it is
    ///         seeded to 0.
    function initializeTick(int24 t) external {
        require(t >= TickMath.MIN_TICK, "tick<MIN");
        require(t <= TickMath.MAX_TICK, "tick>MAX");
        require(!tickInitialized[t], "already init");

        tickInitialized[t] = true;
        if (tick >= t) {
            feeGrowthOutside0X128[t] = feeGrowthGlobal0X128;
            feeGrowthOutside1X128[t] = feeGrowthGlobal1X128;
        }
        // else: outside is the trailing 0; the next cross flips to global.

        emit TickInitialized(t, feeGrowthOutside0X128[t], feeGrowthOutside1X128[t]);
    }

    /// @notice Accrue swap fees to the global (does not touch any tick's
    ///         outside). Mirrors the same `+=` rule as
    ///         `PancakeV3FeeAccountingRef.simulateSwapStep` — kept separate
    ///         from the cross operation so the P-5 surface is exercised
    ///         independently of P-1.
    function swapAccrue(bool zeroForOne, uint256 amountIn) external {
        uint256 capped = amountIn > type(uint128).max ? type(uint128).max : amountIn;
        uint256 feeAmount = (capped * uint256(feePips)) / 1_000_000;

        if (feeAmount > 0) {
            uint256 deltaX128 = (feeAmount * Q128) / uint256(liquidity);
            if (zeroForOne) {
                feeGrowthGlobal0X128 += deltaX128;
            } else {
                feeGrowthGlobal1X128 += deltaX128;
            }
            emit SwapAccrue(zeroForOne, feeAmount, deltaX128);
        }
    }

    /// @notice Cross from the current tick to `newTick`. For each initialized
    ///         tick strictly between them (and including `newTick` per the
    ///         direction), flip `feeGrowthOutside`. This minimal reference
    ///         walks only the destination tick — sufficient to exercise the
    ///         flip rule deterministically; the multi-cross walk is M2
    ///         work and is not the P-5 conservation property.
    function crossTick(int24 newTick) external {
        require(newTick >= TickMath.MIN_TICK, "tick<MIN");
        require(newTick <= TickMath.MAX_TICK, "tick>MAX");

        int24 oldTick = tick;
        if (tickInitialized[newTick] && newTick != oldTick) {
            // The flip uses unchecked subtraction to mirror v3's modular
            // semantics; in the increment-only invariant regime we maintain,
            // `feeGrowthGlobal >= feeGrowthOutside[t]` for every initialized
            // `t` (the P-5 conservation property). A revert here would
            // indicate the property has already been violated; we let the
            // checked subtraction surface that.
            require(
                feeGrowthGlobal0X128 >= feeGrowthOutside0X128[newTick],
                "outside0>global"
            );
            require(
                feeGrowthGlobal1X128 >= feeGrowthOutside1X128[newTick],
                "outside1>global"
            );
            feeGrowthOutside0X128[newTick] = feeGrowthGlobal0X128 - feeGrowthOutside0X128[newTick];
            feeGrowthOutside1X128[newTick] = feeGrowthGlobal1X128 - feeGrowthOutside1X128[newTick];
            emit TickCrossed(oldTick, newTick, newTick);
        }

        tick = newTick;
    }

    // ---------------------------------------------------------------------
    // Views (read helpers for the property tests)
    // ---------------------------------------------------------------------

    /// @notice The "below" fee growth for tick `t` — fees accrued while the
    ///         current tick was at or above `t`. From Uniswap v3 `Tick.sol`.
    function feeGrowthBelow0X128(int24 t) external view returns (uint256) {
        if (tick >= t) {
            return feeGrowthOutside0X128[t];
        }
        return feeGrowthGlobal0X128 - feeGrowthOutside0X128[t];
    }

    /// @notice The "above" fee growth for tick `t` — fees accrued while the
    ///         current tick was strictly below `t`.
    function feeGrowthAbove0X128(int24 t) external view returns (uint256) {
        if (tick < t) {
            return feeGrowthOutside0X128[t];
        }
        return feeGrowthGlobal0X128 - feeGrowthOutside0X128[t];
    }
}
