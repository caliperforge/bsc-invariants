# SCOPE — bsc-invariants

**Single source of truth** for what is covered, what is in-flight, and
what is not started. Updated on every milestone. README headlines must
not exceed what this table records.

**Status legend:**
- ✅ in-tree at HEAD (compiling + green under `forge test`)
- 🟡 in-flight (file present, but not yet green or not yet feature-complete)
- ⬜ M2 / M3 — **not started**

---

## §1 — Protocols × invariants × status

| Protocol | Surface | Invariant ID | Property | Property file | Status | Milestone |
|---|---|---|---|---|---|---|
| **PancakeSwap v3** | Fee accounting | **P-1** | `feeGrowthGlobalXX128` is non-decreasing across any non-protocol-fee swap with non-zero `feePips × amountIn` | `invariants/PancakeV3FeeGrowth.t.sol` | ✅ | M1 |
| **PancakeSwap v3** | Tick math | **P-2** | After any operation, `MIN_TICK ≤ pool.tick ≤ MAX_TICK` | `invariants/PancakeV3TickBounds.t.sol` | ✅ | M1 |
| **PancakeSwap v3** | Tick math | **P-3** | After any operation, `MIN_SQRT_RATIO ≤ pool.sqrtPriceX96 < MAX_SQRT_RATIO` | `invariants/PancakeV3TickBounds.t.sol` | ✅ | M1 |
| **PancakeSwap v3** | Liquidity events | **P-4** | mint/burn updates active `liquidity` by exactly `±delta` for in-range positions; leaves it unchanged otherwise | `invariants/PancakeV3LiquidityEvents.t.sol` | ✅ | M2 |
| **PancakeSwap v3** | Per-tick state | **P-5** | per-initialized-tick `feeGrowthOutside0/1X128 ≤ feeGrowthGlobal` after any sequence of accrues + crosses (increment-only conservation form; wrap-around deferred) | `invariants/PancakeV3FeeGrowthOutside.t.sol` | ✅ | M2 |
| PancakeSwap v3 | Protocol fees | **P-6** | `protocolFees0/1` storage grows by exactly the configured `feeProtocol` fraction of swap fees | — | ⬜ | M2 |
| PancakeSwap v3 | Oracle observations | **P-7** | observation cardinality is monotonic non-decreasing across `increaseObservationCardinalityNext` | — | ⬜ | M2 |
| **PancakeSwap v3** | Planted-twin CI | — | clean + planted CI pair for **P-1** (planted leg surfaces `INVARIANT VIOLATED feeGrowth_neverDecreases` marker, exits non-zero) | `invariants/planted/PancakeV3FeeGrowth.planted.t.sol` | ✅ | M2 |
| PancakeSwap v3 | Planted-twin CI | — | clean + planted CI pair for P-2 + P-3 (planted leg surfaces `INVARIANT VIOLATED` marker, exits non-zero) | `invariants/planted/` | ⬜ | M2 |
| **Venus** | Account liquidity | **V-1** | `getAccountLiquidity(user)` shortfall is consistent with on-chain collateral × `collateralFactor` − borrows × price | — | ⬜ | M2 |
| Venus | Collateral factor | **V-2** | per-market `collateralFactorMantissa ≤ 0.9e18` (Venus governance cap) | — | ⬜ | M2 |
| Venus | Liquidation incentive | **V-3** | `liquidationIncentiveMantissa ≥ 1e18` and seized collateral honors the incentive | — | ⬜ | M2 |
| Venus | XVS rewards | **V-4** | XVS reward accrual per market is bounded by `venusSpeed × blockDelta` | — | ⬜ | M2 |
| **Stargate-on-BSC** | Pool delta accounting | **S-1** | `deltaCredit` + `lkb` (locally booked balance) reconcile with sum of remote-chain credits | — | ⬜ | M3 |
| Stargate-on-BSC | LD/SD conversion | **S-2** | `amountSD = amountLD / convertRate`; round-trip is loss-bounded by `convertRate` | — | ⬜ | M3 |
| Stargate-on-BSC | Credit tracking | **S-3** | `credits[chainId][poolId]` is monotonic between credit-chain-path calls | — | ⬜ | M3 |
| **BNB AI agent-registry** | Identity attestation | **A-1** | (gated on spec landing publicly) | — | ⬜ | M3 |
| BNB AI agent-registry | Reputation-score updates | **A-2** | (gated on spec landing publicly) | — | ⬜ | M3 |

---

## §2 — Surface coverage rationale

**Why the M1 surface is the three properties above (P-1, P-2, P-3) and
not more.** Per the Week-1 dispatch
(`T-bnb-bsc-invariants-week1-2026-06-27`) the explicit scope is
"pool accounting / fee-growth conservation / tick-math bounds as the
first invariants" with "at least one invariant compiling + running
under `forge test` by end of Week 1." Shipping three first-cut
invariants (one fee-growth, two bounds) costs the same engineer-hours
as one and exercises the harness across both `forge test` (unit) and
`invariant_*` (stateful) modes — giving Week 2 a usefully exercised
scaffold to build P-4 / P-5 / P-6 / P-7 on top of, rather than a
single-property foundation.

**Why the M2 Week-2 surface adds P-4, P-5, and the P-1 planted-twin
pair.** Per the Week-2 dispatch
(`T-bnb-bsc-invariants-week2-2026-06-27`), the planted-twin CLEAN/PLANTED
CI pair for P-1 is the differentiator — the demonstration that the
harness can deterministically surface `INVARIANT VIOLATED` when a
planted bug is in place, and pass silently when it is not. P-4 and P-5
round out the core PancakeSwap v3 invariant surface so M1 is
substantive; P-5 is shipped in its increment-only conservation form
(documented gap, wrap-around modelling deferred). P-6 and P-7 remain
M2 work for next week. Venus + Stargate + agent-registry remain
unchanged (M2 / M3, not started).

**Why PancakeSwap v3 is M1, Venus M2, Stargate M3.** Per
`bnb_grant_win_analysis_2026-06-26.md` §3.2, PancakeSwap is the
canonical BSC DEX (largest TVL, most-fork-of-Uniswap-v3 reference
material) and is the lowest-cost surface to port the planted-twin
discipline to. Venus's account-liquidity surface requires modelling
the per-market interest-rate model + the Comptroller, which is M2
effort. Stargate's cross-chain pool delta accounting requires
modelling the credit-chain-path message protocol, which is M3 effort.

**Path-gated CI keeps milestones honest.** Each future protocol's
test file presence is the gate that flips its CI job from `deferred`
to `real-work-green`. The README + this SCOPE table must match the
state of files on disk; the §4b reviewer (independent, not the
solidity_specialist) will check this before any public flip.

---

## §3 — Provenance of upstream constants

- **`MIN_TICK = -887272`, `MAX_TICK = 887272`** — Uniswap v3
  `TickMath.sol` constants; PancakeSwap v3 forks 1:1. Source:
  https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/TickMath.sol
- **`MIN_SQRT_RATIO = 4295128739`** — Uniswap v3 `TickMath.sol`;
  computed as `getSqrtRatioAtTick(MIN_TICK)`.
- **`MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342`** —
  Uniswap v3 `TickMath.sol`; computed as `getSqrtRatioAtTick(MAX_TICK)`.
- **`MAX_LIQUIDITY_PER_TICK`** — derived from `(type(uint128).max) / numTicks`
  per tick spacing; not used in M1 (lands with P-4).

These constants are reproduced in `src/lib/TickMath.sol` with the
attribution header pointing at this section.

---

## §4 — What this scope is NOT

- Not an audit scope.
- Not a runtime monitoring surface.
- Not a Recon Chimera bundle yet (M2 — `invariants/mocks/` ships
  `CryticTester.sol` + `Properties.sol` when the Chimera leg lands).
- Not a Halmos / Certora symbolic surface (deferred until invariants
  stabilize).
