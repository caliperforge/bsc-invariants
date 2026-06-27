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

**Planted-twin twin (LANDED — Week 2).** `invariants/planted/PancakeV3FeeGrowth.planted.t.sol`
instantiates `BrokenPancakeV3FeeAccountingRef` — same interface as the
clean reference with one localized hunk: `feeGrowthGlobal0X128 =
deltaX128` (assignment) instead of the canonical `+=` on the
`zeroForOne` branch. The clean leg
(`invariants/PancakeV3FeeGrowth.t.sol`) passes silently; the planted
leg fires `INVARIANT VIOLATED feeGrowth_neverDecreases (token0)` and
`forge test` exits non-zero. Both are CI-gated by the file-presence
check in `.github/workflows/ci.yml::p1-feegrowth-*`. Receipts in
`receipts/planted_demo/`.

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

---

## P-4 — LiquidityEventConsistency

**Statement.** After any `mint` / `burn` operation on a position
`[tickLower, tickUpper)` with amount `Δ`:

- If `currentTick ∈ [tickLower, tickUpper)` (in-range):
  `liquidity_after - liquidity_before == +Δ` on mint, `−Δ` on burn.
- Otherwise (out-of-range): `liquidity_after == liquidity_before`.

In both cases, the position's per-position liquidity (`positions[key]`)
updates by `±Δ`.

**Why this property.** Uniswap v3's `Pool._modifyPosition` (and its
PancakeSwap v3 mirror) routes a position update through three steps:
(1) update `Tick.update` for both boundaries, (2) update
`Position.update`, (3) IF the current tick is within the position's
range, update the pool's active `liquidity` by `liquidityDelta`. The
"in-range" check is the load-bearing branch — any fork that mis-ports
it (e.g., applies the delta unconditionally, or applies it on the
wrong sign, or applies it for an off-by-one `tickUpper` boundary)
desyncs active liquidity from the set of currently-active LPs.

**Citation.** Uniswap v3 `UniswapV3Pool.sol::_modifyPosition` —
function body, the
`if (params.tickLower <= state.tick && state.tick < params.tickUpper)`
branch. PancakeSwap v3 mirror at the same path.

**Bug class caught.** A forked v3 pool whose `_modifyPosition`:
- applies `liquidityDelta` unconditionally (no in-range check),
- applies it with the wrong sign,
- uses `<=` instead of `<` on the upper boundary (off-by-one
  ambiguity at exactly `tickUpper`),
- or fails to apply it for in-range positions.

The downstream effect is swap fee accrual to LPs that have no
liquidity in range, or non-accrual to LPs that do.

**Test plan.** `invariants/PancakeV3LiquidityEvents.t.sol`:
- `test_property_mint_inRange_incrementsByDelta` — boundary unit.
- `test_property_mint_outOfRange_leavesActiveUnchanged` — out-of-range case.
- `test_property_burn_inRange_decrementsByDelta` — symmetric burn.
- `test_property_burn_outOfRange_leavesActiveUnchanged` — out-of-range burn.
- `test_property_crossTick_thenMint_inRange_activates` — cross-then-mint sanity.
- `test_property_positionLiquidity_alwaysIncrementsOnMint` — position-side accounting.
- `testFuzz_property_mint_inRange_incrementsByDelta` — fuzz amount.
- `invariant_activeLiquidity_equalsNetMintMinusBurn_inRange` — stateful fuzz comparing pool active liquidity to a sum-of-mints-minus-burns shadow under a clamped tick band.

**Planted-twin twin (M2 — Week 3 work).** Not yet landed; the planted
hunk will drop the `if (inRange)` check from `mint` so out-of-range
mints leak into active liquidity.

---

## P-5 — FeeGrowthOutsideConsistency

**Statement.** For every initialized tick `t`, at all times:

- `feeGrowthOutside0X128[t] ≤ feeGrowthGlobal0X128`
- `feeGrowthOutside1X128[t] ≤ feeGrowthGlobal1X128`

after any sequence of `initializeTick`, `swapAccrue`, and
`crossTick`. The init + flip rules:

- On `initializeTick(t)`: if `currentTick ≥ t`, seed
  `feeGrowthOutside[t] = feeGrowthGlobal`; else seed `0`.
- On `crossTick(t)`: `feeGrowthOutside[t] := feeGrowthGlobal − feeGrowthOutside[t]`.

The flip preserves the bound: post-flip outside = old "below" amount,
which is non-negative and bounded by global.

**What this models (and what it does not).** This is the
**increment-only conservation form** of P-5. Real Uniswap v3 stores
both global and outside as `uint256` and admits wrap-around — the
`(global − outside)` subtraction recovers position-local growth
modulo 2^256, and `outside > global` is a legitimate state mid-wrap.
The increment-only form is strictly conservative for any swap
sequence that does not cross the wrap boundary (the operative case for
any realistic pool). The wrap-around variant is documented as a
Week-3 add (see RUN_SUMMARY §W2-6).

**Why this property.** Uniswap v3's per-LP fee withdrawal computes
`feeGrowthInside(L, U) = feeGrowthGlobal − feeGrowthBelow(L) − feeGrowthAbove(U)`
where the "below" / "above" amounts are derived from `feeGrowthOutside`.
The flip rule is the load-bearing operation that keeps "outside"
aligned with the pool's current tick relative to `t`. Any fork that
mis-ports `Tick.cross` or `Tick.update` desyncs this computation and
LPs over-withdraw or under-withdraw.

**Citation.** Uniswap v3 `Tick.sol::update` (the
`tickCurrent >= tick` branch — the init rule) and
`Tick.sol::cross` (the flip rule). PancakeSwap v3 mirror at the
same path.

**Bug class caught.** A fork whose `Tick.cross`:
- skips the flip,
- flips on the wrong branch direction,
- or computes the flip as `outside − global` (sign-inverted).

Also catches a fork whose `Tick.update` initializes outside on the
wrong branch of `tickCurrent >= tick`.

**Test plan.** `invariants/PancakeV3FeeGrowthOutside.t.sol`:
- `test_property_initialize_belowCurrent_seedsOutsideEqualsGlobal` — init below current.
- `test_property_initialize_aboveCurrent_seedsOutsideZero` — init above current.
- `test_property_crossUp_flipsOutside_toGlobalMinusOldOutside` — flip rule.
- `test_property_doubleCross_isInvolutive` — double-flip restores original.
- `test_property_outside_neverExceedsGlobal_afterAccrues` — bound after accrues.
- `testFuzz_property_outside_boundedAfterSwap` — fuzz swap amounts preserve bound.
- `invariant_feeGrowthOutside_bounded_byGlobal` — stateful fuzz over three initialized ticks under accrue + cross fuzzing.

**Planted-twin twin (M2 — Week 3 work).** Not yet landed; the planted
hunk will invert the flip direction (`outside − global` instead of
`global − outside`) so the conservation property fires on the first
crossing.

---

## What is M2 (next milestone, partial — P-4 + P-5 landed in Week 2)

- **P-4 — LiquidityEventConsistency.** ✅ Landed Week 2 (above).
- **P-5 — FeeGrowthOutsideConsistency** (increment-only form). ✅ Landed Week 2 (above); wrap-around variant deferred to Week 3.
- **P-6 — ProtocolFeeAccrualBound.** `protocolFees0/1` storage grows
  by exactly the configured `feeProtocol` fraction of swap fees;
  `feeGrowthGlobal` is correspondingly reduced. Week 3.
- **P-7 — ObservationCardinalityMonotonicity.** Oracle observation
  cardinality is monotonic non-decreasing across
  `increaseObservationCardinalityNext`. Week 3.
- **Planted-twin CI pair for P-1.** ✅ Landed Week 2.
- **Planted-twin CI pairs for P-2 + P-3.** Week 3.
- **BSC-mainnet fork tests** at a pinned block. Week 3.

## What is M3 (not in v0.0.1)

- **V-1 .. V-4 — Venus lending invariants.** See `SCOPE.md` §1.
- **S-1 .. S-3 — Stargate-on-BSC bridge invariants.**
- **A-1 .. A-2 — BNB Chain AI agent-registry harness** (gated on the
  spec landing publicly per 2026 Tech Roadmap).
