# bsc-invariants (v0.0.2, Weeks 1 + 2)

**Status.** Weeks 1 + 2 of the BNB grant build-to-win. PancakeSwap v3
invariants P-1 (FeeGrowthGlobalMonotonicity), P-2 (TickInBounds), P-3
(SqrtPriceX96InBounds), P-4 (LiquidityEventConsistency), and P-5
(FeeGrowthOutsideConsistency, increment-only conservation form) are
in-tree and pass under `forge test` (31 / 31 green). The P-1 planted-twin
CI pair has also landed and surfaces `INVARIANT VIOLATED` deterministically
on the planted leg. P-6, P-7, P-2 / P-3 planted twins, the wrap-around
P-5 variant, and BSC-mainnet fork tests are Week-3 work and are NOT in
the tree. Venus and Stargate harnesses are M2 / M3 and are **not started**.
This README claims only what ships at HEAD.

---

## What this library is

> **What this is.** `bsc-invariants` is an open-source library of
> invariants and CI-runnable property tests for BNB Smart Chain DeFi
> protocols, starting with PancakeSwap v3 (the canonical BSC DEX).
> Each invariant is paired with a same-source twin discipline: a
> clean reference where the property holds under fuzz, and (at M2) a
> planted-bug twin where the property fires with a deterministic
> `INVARIANT VIOLATED` marker. The library extends the planted-twin
> discipline already shipped on HyperEVM (`hyperevm-safety`) and
> Ethereum mainnet (Lido EVM probe). **What this isn't.** Not an
> audit. Not a runtime monitor. Not a SaaS product. Not (yet) a
> broad coverage of the BSC DeFi stack: PancakeSwap v3 is
> M1; Venus is M2; Stargate-on-BSC is M3. The thesis is reputation
> → grant upside + downstream integration as the safety-rating
> primitive layer the BNB Chain wishlist's "Risk Scoring Frameworks"
> category asks for; the artifact ships as a public good under
> Apache-2.0.

**M-status addendum (Week 2, HEAD).** The P-1 planted-bug twin has
landed: `invariants/planted/PancakeV3FeeGrowth.planted.t.sol` fires
`INVARIANT VIOLATED feeGrowth_neverDecreases` deterministically and
`forge test` exits non-zero on the planted leg. P-2 and P-3 planted
twins are Week-3 work; see `SCOPE.md` §1.

---

## What this library does NOT claim

- **Not an audit.** A passing CI run on a fork of this library against
  a protocol's contracts does not certify the protocol is safe. The
  library catches the bug classes the invariants encode; the residual
  surface is the protocol's.
- **Not a runtime monitor.** The properties are pre-deploy CI gates.
- **Not yet broad-coverage.** Only PancakeSwap v3 has any invariants
  in-tree at v0.0.2. Venus and Stargate are M2 / M3 and explicitly
  not started.
- **Not a fork of PancakeSwap production source.** The reference
  contract under `src/PancakeV3FeeAccountingRef.sol` is a same-source
  twin minimal to the invariants under test. Where v3-core math
  constants are reproduced (`src/lib/TickMath.sol`), the upstream
  attribution lives in `NOTICE`.

---

## Invariants in v0.0.2 (the product)

Five invariants and a planted-twin CI pair land at the PancakeSwap v3
pool boundary. Each row maps a property in `invariants/` to the
upstream v3 statement it tests. Full prose lives in
[`docs/invariants.md`](docs/invariants.md); the in-code NatSpec is
the single source of truth for the precise statement.

| ID | Invariant | Reference under test | Property bundle |
|---|---|---|---|
| **P-1** | FeeGrowthGlobalMonotonicity | [`PancakeV3FeeAccountingRef.sol`](src/PancakeV3FeeAccountingRef.sol) | [`PancakeV3FeeGrowth.t.sol`](invariants/PancakeV3FeeGrowth.t.sol) |
| **P-2** | TickInBounds (MIN_TICK ≤ tick ≤ MAX_TICK) | [`PancakeV3FeeAccountingRef.sol`](src/PancakeV3FeeAccountingRef.sol) | [`PancakeV3TickBounds.t.sol`](invariants/PancakeV3TickBounds.t.sol) |
| **P-3** | SqrtPriceX96InBounds (MIN_SQRT_RATIO ≤ sqrtPriceX96 < MAX_SQRT_RATIO) | [`PancakeV3FeeAccountingRef.sol`](src/PancakeV3FeeAccountingRef.sol) | [`PancakeV3TickBounds.t.sol`](invariants/PancakeV3TickBounds.t.sol) |
| **P-4** | LiquidityEventConsistency (mint / burn updates active liquidity by exactly ±Δ for in-range positions; unchanged out-of-range) | [`PancakeV3LiquidityEventsRef.sol`](src/PancakeV3LiquidityEventsRef.sol) | [`PancakeV3LiquidityEvents.t.sol`](invariants/PancakeV3LiquidityEvents.t.sol) |
| **P-5** | FeeGrowthOutsideConsistency (per-initialized-tick `feeGrowthOutside ≤ feeGrowthGlobal`, increment-only form) | [`PancakeV3FeeGrowthOutsideRef.sol`](src/PancakeV3FeeGrowthOutsideRef.sol) | [`PancakeV3FeeGrowthOutside.t.sol`](invariants/PancakeV3FeeGrowthOutside.t.sol) |
| **P-1 planted** | Planted-twin CI pair (planted leg surfaces `INVARIANT VIOLATED feeGrowth_neverDecreases`, exits non-zero) | inline `BrokenPancakeV3FeeAccountingRef` (hyperevm-safety convention) | [`PancakeV3FeeGrowth.planted.t.sol`](invariants/planted/PancakeV3FeeGrowth.planted.t.sol) |

P-1 is the highest-priority invariant. The bug class it catches,
fee-growth accounting that decreases under any non-zero swap, is the
exact failure mode of Uniswap-v3-fork forks that mis-port the
`feeGrowthGlobalX128 += FullMath.mulDiv(...)` increment: the
canonical accounting bug forks introduce when refactoring the pool.

The PancakeSwap v3 invariants and surfaces covered (and not) are
catalogued in [`SCOPE.md`](SCOPE.md).

---

## Repo layout

```
experiments/bsc-invariants/
  README.md                  # this file
  LICENSE                    # Apache-2.0 (born-with-license rule)
  NOTICE                     # upstream attributions
  AI_DISCLOSURE.md           # AI-touched surfaces + review discipline
  SECURITY.md                # responsible disclosure
  SCOPE.md                   # protocols x invariants x status (M1/M2/M3)
  RUN_SUMMARY.md             # Weeks 1+2 run summary (what shipped vs deferred)
  foundry.toml               # Foundry config (solc 0.8.28, CI fuzz budgets, [fmt] pin)
  remappings.txt             # forge-std remapping
  .gitignore
  .github/
    workflows/ci.yml         # path-gated CI: each M2/M3 job flips on file presence
    actions/foundry-setup/   # composite action: pinned Foundry + forge-std install
  src/
    lib/TickMath.sol                       # v3 tick/sqrtPriceX96 constants (attributed in NOTICE)
    PancakeV3FeeAccountingRef.sol          # minimal v3 reference for P-1/P-2/P-3
    PancakeV3FeeGrowthOutsideRef.sol       # per-tick feeGrowthOutside reference for P-5
    PancakeV3LiquidityEventsRef.sol        # mint/burn + active-liquidity reference for P-4
  invariants/
    PancakeV3FeeGrowth.t.sol               # P-1: fee-growth global monotonicity
    PancakeV3TickBounds.t.sol              # P-2 + P-3: tick + sqrtPriceX96 bounds
    PancakeV3LiquidityEvents.t.sol         # P-4: liquidity-event consistency
    PancakeV3FeeGrowthOutside.t.sol        # P-5: per-tick feeGrowthOutside conservation
    mocks/                                 # M2/Week-3: Recon Chimera CryticTester scaffold lands here
    planted/
      PancakeV3FeeGrowth.planted.t.sol     # P-1 planted twin (Week 2, LANDED)
  docs/
    invariants.md                          # prose invariant descriptions + upstream citations
  receipts/
    forge-build-*.log                      # forge build receipts (Weeks 1+2)
    forge-test-*.log                       # forge test receipts (Weeks 1+2)
    planted_demo/p1-*.log                  # P-1 planted-twin clean + planted leg receipts
```

---

## Running locally

```bash
# Install Foundry (https://book.getfoundry.sh/getting-started/installation)
curl -L https://foundry.paradigm.xyz | bash && foundryup

# From this directory
forge install foundry-rs/forge-std@v1.9.4 --no-commit  # pinned per CI
forge build
forge test -vv
```

Expected: all five invariants (P-1, P-2, P-3, P-4, P-5) plus the P-1
planted-twin pair pass against the clean references (31 / 31 green;
the planted leg exits non-zero and surfaces `INVARIANT VIOLATED`).
Fuzz budget is small (1000 runs) for fast local iteration; the CI
`nightly` workflow (M2/Week-3) will run longer campaigns.

**Formatting.** `forge fmt` style is pinned in `foundry.toml` under
`[fmt]` (line length 120, all-line multiline function headers) so the
hand-tuned multi-line argument layouts in the references and tests
survive a re-format pass.

---

## CI

`.github/workflows/ci.yml` runs `forge build` and `forge test` against
the clean reference. Each M2 / M3 PancakeSwap-extension job and each
M2 Venus / M3 Stargate job is **path-gated**: the job inspects the
filesystem and either runs (when the wiring file exists) or emits a
GitHub Actions `::notice::` line explaining what is deferred. This
keeps the CI graph stable across milestones; a new harness flips its
own job from `deferred` to `real-work-green` the moment the wiring
file lands.

The current CI status (from the run log, not the badge) is recorded
in [`RUN_SUMMARY.md`](RUN_SUMMARY.md) §3.

---

## Roadmap (NOT YET IN-TREE; see SCOPE.md)

- **M2 / Week 3, PancakeSwap v3 remainder.** P-6 protocol-fee accrual
  bound, P-7 oracle observation cardinality monotonicity, planted-twin
  CI pairs for P-2 + P-3, the wrap-around variant of P-5, the first
  BSC-mainnet fork test against a real PancakeSwap v3 pool at a pinned
  block, and the Recon Chimera `Properties.sol` + `CryticTester.sol`
  scaffold.
- **M2, Venus lending invariants.** Account-liquidity correctness,
  collateral-factor bounds, liquidation-incentive monotonicity, XVS
  reward-accrual bounds (the bug class behind the 2021
  XVS-collateral incident).
- **M3, Stargate-on-BSC bridge invariants.** Pool delta accounting
  across chain-id pairs, LD/SD conversion safety, credit-tracking
  monotonicity.
- **M3, BNB Chain AI agent-registry harness.** Invariant + verifiable-
  capability test harness against the 2026 Tech Roadmap's agent
  registry spec (gated on the spec landing publicly).

---

## License

Apache License 2.0; see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

## Contact

CaliperForge: michael@caliperforge.com, team@caliperforge.com.
