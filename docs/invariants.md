# Invariants — bsc-invariants (v0.0.1)

This document is the prose source of truth for each invariant in the
library. The in-code NatSpec on the property file is the precise
mechanical statement; this doc explains the bug class, the upstream
citation, and the test plan.

## P-1 — FeeGrowthGlobalMonotonicity

**Statement.** After any sequence of swap operations on a PancakeSwap
v3 pool, `feeGrowthGlobal0X128` and `feeGrowthGlobal1X128` are
non-decreasing.

**Why this property.** Uniswap v3's accounting model stores
per-unit-of-liquidity cumulative fees as `feeGrowthGlobalXX128`. The
canonical update is:

```solidity
state.feeGrowthGlobalX128 += FullMath.mulDiv(step.feeAmount, FixedPoint128.Q128, state.liquidity);
```

(See Uniswap v3 `UniswapV3Pool.sol::swap` — function body, the inner
loop step. PancakeSwap v3 ports this 1:1.) The `+=` is the load-bearing
operation; any forked pool that rewrites this loop is at risk of
inverting the sign (the common port bug) or accidentally subtracting
on a refund-path. Position-level fee withdrawal then over-credits or
under-credits LPs depending on which direction the bug points.

**Citation.** Uniswap v3 whitepaper §6.3 ("Tracking fees and liquidity
positions") + `UniswapV3Pool.sol::swap`. PancakeSwap v3 mirror at
`pancakeswap/pancake-v3-contracts/projects/v3-core/contracts/PancakeV3Pool.sol`.

**Bug class caught.** Fee-growth decrement on a swap path; signed
conversion error in a fork that switches the accumulator type;
withdrawProtocolFee accidentally touching `feeGrowthGlobal` instead of
`protocolFees`.

**Test plan.**
- `test_property_swapToken0_increasesFee0_onlyFee0` — deterministic
  unit boundary.
- `test_property_swapToken1_increasesFee1_onlyFee1` — symmetric.
- `test_property_zeroAmount_noFeeChange` — no spurious accrual on
  empty swaps.
- `testFuzz_property_nonZeroAmount_strictIncrease` — fuzz the
  amount-in.
- `invariant_feeGrowth_neverDecreases` — stateful-fuzz invariant
  comparing pool state against a shadow last-observed value, so a
  single decrement trips the marker on the very next pass.

**Planted-twin twin (M2).** `invariants/planted/PancakeV3FeeGrowth.planted.t.sol`
will instantiate a planted reference that swaps the `+=` for a `-=`
on the token0 fee-growth path. The clean leg passes silently; the
planted leg fires `INVARIANT VIOLATED feeGrowth_neverDecreases (token0)`
and `forge test` exits non-zero.

---

## P-2 — TickInBounds

**Statement.** After any operation, the pool's `tick` lies in
`[MIN_TICK, MAX_TICK] = [-887272, 887272]`.

**Why this property.** Uniswap v3's tick address space is bounded by
the `getSqrtRatioAtTick` numeric range. `MIN_TICK` / `MAX_TICK` are
the smallest / largest ticks for which the sqrt-ratio computation
does not overflow `uint160`. The pool's swap routine includes
explicit `require(tickNext >= MIN_TICK && tickNext <= MAX_TICK)`
checks at each tick-cross step.

**Citation.** Uniswap v3 `TickMath.sol` (constants) +
`UniswapV3Pool.sol::swap` (the tick-cross loop). Same PancakeSwap
v3 mirror as P-1.

**Bug class caught.** A fork that drops the bound check from
SwapMath's tick-cross loop. The downstream effect is a pool whose
`getSqrtRatioAtTick(tick)` overflows on subsequent reads, bricking
the pool or producing garbage prices.

**Test plan.** See `invariants/PancakeV3TickBounds.t.sol` § P-2
section — boundary tests at MIN, MAX, MIN-1, MAX+1, plus a fuzz pass
on `tickDelta`.

**Planted-twin twin (M2).** Same pattern as P-1: the planted leg
removes the `require(tick >= MIN_TICK && tick <= MAX_TICK)` checks
from `simulateSwapStep`.

---

## P-3 — SqrtPriceX96InBounds

**Statement.** After any operation, the pool's `sqrtPriceX96` lies in
`[MIN_SQRT_RATIO, MAX_SQRT_RATIO)`. The upper bound is **strict** —
`MAX_SQRT_RATIO` itself is rejected; the largest admitted value is
`MAX_SQRT_RATIO - 1`.

**Why this property.** Same address-space argument as P-2:
sqrtPriceX96 is bounded by the values reachable from
`getSqrtRatioAtTick(MIN_TICK..MAX_TICK)`. The asymmetry (`MIN_SQRT_RATIO`
inclusive, `MAX_SQRT_RATIO` exclusive) is documented in Uniswap v3
`TickMath.sol` as a numerical convenience that keeps the
`SqrtPriceMath` computations safely inside `uint160`.

**Bug class caught.** A fork whose `nextSqrtPriceFromInput` /
`nextSqrtPriceFromOutput` routine doesn't clamp to
`MAX_SQRT_RATIO - 1`. The downstream effect is the same as P-2: an
out-of-range sqrtPriceX96 makes subsequent `getTickAtSqrtRatio` reads
return undefined values.

**Test plan.** See `invariants/PancakeV3TickBounds.t.sol` § P-3
section — boundary tests at MIN, MAX-1, MIN-1, MAX.

**Planted-twin twin (M2).** The planted leg relaxes the
`require(sqrt < MAX_SQRT_RATIO)` to `require(sqrt <= MAX_SQRT_RATIO)`
to admit the off-by-one.

---

## What is M2 (next milestone, NOT in v0.0.1)

- **P-4 — LiquidityEventConsistency.** mint/burn updates `liquidity`
  by exactly `±delta` for in-range positions; out-of-range positions
  leave `liquidity` untouched.
- **P-5 — FeeGrowthOutsideConsistency.** `feeGrowthOutside0/1X128`
  per tick is conserved across crossings: at any tick, the
  in-range-since-last-cross fees plus the outside-of-range fees sum
  to `feeGrowthGlobal`.
- **P-6 — ProtocolFeeAccrualBound.** `protocolFees0/1` storage grows
  by exactly the configured `feeProtocol` fraction of swap fees;
  `feeGrowthGlobal` is correspondingly reduced.
- **P-7 — ObservationCardinalityMonotonicity.** Oracle observation
  cardinality is monotonic non-decreasing across
  `increaseObservationCardinalityNext`.
- **Planted-twin CI pairs** for P-1, P-2, P-3 (lands the
  deterministic `INVARIANT VIOLATED` pattern that the CI workflow's
  `*-planted-fires` jobs gate on).

## What is M3 (not in v0.0.1)

- **V-1 .. V-4 — Venus lending invariants.** See `SCOPE.md` §1.
- **S-1 .. S-3 — Stargate-on-BSC bridge invariants.**
- **A-1 .. A-2 — BNB Chain AI agent-registry harness** (gated on the
  spec landing publicly per 2026 Tech Roadmap).
