# bsc-invariants RUN_SUMMARY (Weeks 1+2, 2026-06-27)

The Week-2 update lives at the bottom of this file (`§W2-1` ... `§W2-7`).
Week-1 sections remain unchanged for provenance.

---

# Week 1: initial scaffold

**Repo target:** `experiments/bsc-invariants/` (will land at `github.com/caliperforge/bsc-invariants` on the public flip, gated on §4b code-quality reviewer PASS + CEO greenlight).
**Owner:** Solidity Specialist.
**Dispatch:** `T-bnb-bsc-invariants-week1-2026-06-27` (Director, per CEO greenlight `D-bnb-grant-greenlight-2026-06-27`).
**Source pattern (port-from):** `experiments/hyperevm-safety/`, Foundry harness + planted-twin discipline + path-gated CI.
**Scope source:** `agents/research_lead/outbox/bnb_grant_win_analysis_2026-06-26.md` §3.2.

---

## §1. What shipped (Week 1)

The minimal-winning-build §3.2 elements B2 + B3 + SCOPE table:

1. **Repo scaffold.** `experiments/bsc-invariants/` with the born-with-license discipline (Apache-2.0 `LICENSE` + `NOTICE` from commit one). Files: `README.md`, `LICENSE`, `NOTICE`, `AI_DISCLOSURE.md`, `SECURITY.md`, `SCOPE.md`, `.gitignore`, `foundry.toml`, `remappings.txt`.
2. **CI wiring.** `.github/workflows/ci.yml` mirrors the `hyperevm-safety` pattern, `library-build` + `library-properties-clean` for M1, plus four path-gated jobs for M2 / M3 (P-1 planted-twin clean leg + planted leg, Venus harness build, Stargate harness build). Each future job flips from `deferred` to `real-work-green` the moment its wiring file lands. Composite Foundry-setup action at `.github/actions/foundry-setup/`.
3. **PancakeSwap v3 invariant harness v0.**
   - `src/lib/TickMath.sol`, Uniswap v3 / PancakeSwap v3 address-space constants (MIN_TICK = -887272, MAX_TICK = 887272, MIN_SQRT_RATIO = 4295128739, MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342). Attribution in `NOTICE` (constants are facts; implementations not reproduced).
   - `src/PancakeV3FeeAccountingRef.sol`, minimal same-source reference modelling the v3 fee-growth `+=` update, the tick + sqrtPriceX96 state, and bound-enforcing `require` checks.
   - `invariants/PancakeV3FeeGrowth.t.sol`, **P-1 FeeGrowthGlobalMonotonicity** with one stateful-fuzz invariant (`invariant_feeGrowth_neverDecreases`) + 4 unit/fuzz property tests + a bounded handler so the fuzzer hits in-bound inputs.
   - `invariants/PancakeV3TickBounds.t.sol`, **P-2 TickInBounds** (5 tests) + **P-3 SqrtPriceX96InBounds** (5 tests + 1 fuzz).
4. **SCOPE.md surface table.** Protocols × invariants × status × milestone, single source of truth for what is in-tree vs M2 / M3 / not-started. README + RUN_SUMMARY must not exceed this table.
5. **`docs/invariants.md`**, prose statement + bug-class + upstream citation per invariant.

Week-1 acceptance criterion ("at least one invariant compiling + running under `forge test` by end of Week 1") **PASSES**, 16 tests across 2 suites, all green; see §3.

## §2. What is M2 / M3 / not-started

Per `SCOPE.md` §1:

- **M2 (Week 2 / Week 3, planned):** P-4 LiquidityEventConsistency, P-5 FeeGrowthOutsideConsistency, P-6 ProtocolFeeAccrualBound, P-7 ObservationCardinalityMonotonicity, planted-twin CI pairs for P-1 / P-2 / P-3 (the deterministic `INVARIANT VIOLATED` pattern the CI's `*-planted-fires` jobs gate on), Recon Chimera `Properties.sol` + `CryticTester.sol` scaffold. **Not started.**
- **M2 (out of Week 1 scope per dispatch):** Venus lending invariants V-1 / V-2 / V-3 / V-4. **Not started.**
- **M3 (out of Week 1 scope per dispatch):** Stargate-on-BSC bridge invariants S-1 / S-2 / S-3 + BNB Chain AI agent-registry harness A-1 / A-2. **Not started.**

The Venus + Stargate + agent-registry surfaces are NOT touched. CI carries path-gated placeholder jobs so the graph stays stable when those harnesses land; today those jobs emit `::notice::` lines explaining the deferral.

## §3. CI status (from log, not the badge)

GitHub Actions has not yet run (repo is private, no remote push yet; public flip is §4b + CEO-gated). The local proof is the `forge test` run captured in `receipts/forge-test-2026-06-27.log`. Tail of the run:

```
Ran 11 tests for invariants/PancakeV3TickBounds.t.sol:PancakeV3TickBoundsTest
  ... 11 PASS (incl. testFuzz_property_tickAlwaysInBounds, 1000 fuzz runs)
Suite result: ok. 11 passed; 0 failed; 0 skipped; finished in 19.11ms

Ran 5 tests for invariants/PancakeV3FeeGrowth.t.sol:PancakeV3FeeGrowthTest
  [PASS] invariant_feeGrowth_neverDecreases() (runs: 256, calls: 12800, reverts: 0)
  ... 4 more PASS (incl. testFuzz_property_nonZeroAmount_strictIncrease, 1000 fuzz runs)
Suite result: ok. 5 passed; 0 failed; 0 skipped; finished in 1.08s

Ran 2 test suites in 1.09s (1.10s CPU time): 16 tests passed, 0 failed, 0 skipped
```

**16 / 16 tests pass**, 1 stateful-fuzz invariant (256 runs × 50 depth = 12,800 calls; 0 reverts), 2 fuzz tests (1000 runs each), 13 unit/boundary tests.

`forge build` is clean (compiler run successful). It emits `unsafe-typecast` and `mixed-case-function` lints on the reference and tests, these are advisory only (the truncations are bound-protected by `require` checks; the mixed-case names are forge-std-style `test_property_*`). They are NOT errors and do not gate the build; we will quiet them in M2 with the documented `forge-lint: disable-next-line` annotations once the surface stabilizes. Full build log at `receipts/forge-build-2026-06-27.log`.

CI-on-GitHub status (once the repo lands on a remote and a push runs): the `library-build` + `library-properties-clean` jobs should mirror the local pass; the four M2/M3 path-gated jobs will emit `::notice:: ... deferred` lines (this is the expected `wired=false` path).

## §4. Files written / changed

```
experiments/bsc-invariants/
  AI_DISCLOSURE.md                                    NEW
  LICENSE                                             NEW (Apache-2.0 verbatim, ported from hyperevm-safety)
  NOTICE                                              NEW
  README.md                                           NEW
  RUN_SUMMARY.md                                      NEW (this file)
  SCOPE.md                                            NEW
  SECURITY.md                                         NEW
  .gitignore                                          NEW
  foundry.toml                                        NEW
  remappings.txt                                      NEW
  .github/actions/foundry-setup/action.yml            NEW
  .github/workflows/ci.yml                            NEW
  docs/invariants.md                                  NEW
  invariants/PancakeV3FeeGrowth.t.sol                 NEW
  invariants/PancakeV3TickBounds.t.sol                NEW
  invariants/mocks/                                   NEW (empty; M2 Recon Chimera lands here)
  invariants/planted/                                 NEW (empty; M2 planted twins land here)
  receipts/forge-build-2026-06-27.log                 NEW
  receipts/forge-test-2026-06-27.log                  NEW
  src/PancakeV3FeeAccountingRef.sol                   NEW
  src/lib/TickMath.sol                                NEW
```

No other paths in the repo touched. No `git add -A`; the Build Engineer / Director will scope the commit set deliberately per dispatch discipline ("Do NOT run git commit").

**Secret-scan note.** No `.env`, credentials, or tokens written. The `.gitignore` includes the standard Foundry + env patterns from the start.

## §5. Receipts & reproduction

- `receipts/forge-build-2026-06-27.log`, full `forge build` output (compiler run successful + advisory lint warnings).
- `receipts/forge-test-2026-06-27.log`, full `forge test -vv` output (16 / 16 pass).

To reproduce locally:

```bash
cd experiments/bsc-invariants
forge install foundry-rs/forge-std@v1.9.4
forge build
forge test -vv
```

Provenance: tested against `lib/forge-std @ v1.9.4` (tag `1eea5bae12ae557d589f9f0f0edae2faa47cb262`) on Foundry `1.7.1` (commit `4072e48705af9d93e3c0f6e29e93b5e9a40caed8`), solc 0.8.28, on macOS arm64 (operator host) at 2026-06-27.

## §6. Known gaps + Week 2 plan

**Honest gaps in v0.0.1:**

1. **The reference is "increment-only" arithmetic**, real Uniswap v3 / PancakeSwap v3 stores `feeGrowthGlobalXX128` as `uint256` and ALLOWS wrap-around; position-local growth is recovered modulo 2^256 via the `(global - outside)` subtraction. Modelling that wrap is M2 work (P-5 fee-growth-outside consistency). For Week 1, the increment-only reference is the conservative model, P-1 holds on the increment-only reference iff it holds on the wrapping reference under any sequence of inputs that doesn't cross the wrap boundary, which is the operative case for any realistic swap sequence. Documented in `src/PancakeV3FeeAccountingRef.sol` NatSpec + `docs/invariants.md` P-1 § "Test plan."
2. **No planted-twin clean/planted CI pair yet.** Lands at M2. The CI workflow's `p1-feegrowth-clean-passes` + `p1-feegrowth-planted-fires` jobs are already wired and gate on `invariants/planted/PancakeV3FeeGrowth.planted.t.sol`'s file presence; they emit `::notice:: ... deferred` today.
3. **No Recon Chimera bundle yet.** Lands at M2 alongside the planted twins (`invariants/mocks/CryticTester.sol` + `invariants/mocks/Properties.sol`).
4. **Tick math `getSqrtRatioAtTick` implementation not reproduced.** Only the bound constants are needed for the M1 invariants; if M2 invariants need the function body (P-5 likely will, for cross-tick fee-growth fragment accounting), we either vendor the upstream GPL file with its full header + re-evaluate the repo's license posture, OR link upstream as a git submodule. Decision deferred to the M2 design step (`SCOPE.md` §3).
5. **No fork tests against deployed PancakeSwap v3 mainnet pools.** Lands at M2, the reference contract proves the invariants on a self-contained twin; the fork test proves the invariants on a real pool at a pinned block. This is the highest-value M2 add for the grant application narrative (lets us claim "tested against PancakeSwap v3 at BSC block X" rather than "tested against a reference").

**Week 2 plan (per `bnb_grant_win_analysis_2026-06-26.md` §4.2 B5 + B6):**

- **B5:** ship P-4 / P-5 / P-6 / P-7 (the remaining PancakeSwap v3 invariants) + the first planted-twin CI pair for P-1.
- **B6:** finish `docs/invariants.md` for all 7 properties + first BSC-mainnet fork test against a real PancakeSwap v3 pool at a pinned block.
- Pull a code_quality_reviewer §4b review on what landed Week 1 + 2 before any public flip is even queued.

## §7. Discipline checklist

- [x] Apache-2.0 LICENSE from FIRST commit
- [x] NOTICE with upstream attributions (Uniswap v3, PancakeSwap v3, hyperevm-safety, chimera-template-pack, invariant-atlas, toolchain)
- [x] README claims only what ships at HEAD; M2 / M3 work labelled explicitly as "not started"
- [x] SCOPE.md is the single source of truth; README + RUN_SUMMARY do not exceed it
- [x] AI_DISCLOSURE.md per CaliperForge register
- [x] SECURITY.md per disclosure norm
- [x] No `git commit` run (Director/Build Engineer commits after review)
- [x] No `git add -A`; file list above is scoped
- [x] No secrets / `.env` / credentials in any written file
- [x] CI status reported from log, not from a (non-existent) badge
- [x] Repo private; no public flip (§4b + CEO gates remain)
- [x] No nested sub-agents spawned
- [x] One-line receipt to Director will be written to `agents/solidity_specialist/outbox/` per role hand-off convention

## §8. Decision queued for CEO

None new from this dispatch. Carried forward (from the Research Lead's §5):

- **`D-bnb-grant-ask-band-2026-06-26`**, ratify the $80K mid-band ask (3 deliverables across PancakeSwap v3 + Venus + Stargate + agent-registry). Solidity Specialist surfaces this as the design choice baked into the SCOPE table's milestone partitioning. CEO call.

**Operational decision (Director-level, not CEO):** the §4b code-quality reviewer (`code_quality_reviewer`, NOT the solidity_specialist who built this) must audit the Week 1 + Week 2 scaffold against the `agents/ai_ops/policies/code_authoring_standard.md` ruleset BEFORE any public flip. The §4b review should happen end of Week 2; the public flip is CEO-gated and additionally awaits the Chrome/Playwright form walk (`bnb_grant_win_analysis_2026-06-26.md` §10).

---

# Week 2: planted-twin CI demo + core invariant build-out

**Dispatch:** `T-bnb-bsc-invariants-week2-2026-06-27` (Director, per CEO greenlight `D-bnb-grant-greenlight-2026-06-27`).
**Builds on:** Week-1 commit `5bb0b2e` (16/16 forge green).
**Date:** 2026-06-27.

## §W2-1. What shipped (Week 2)

Three deliverables per the Week-2 dispatch:

1. **Planted-twin CI pair for P-1 (FeeGrowthGlobalMonotonicity)**, the headline differentiator. New file: `invariants/planted/PancakeV3FeeGrowth.planted.t.sol`. Hosts:
   - `BrokenPancakeV3FeeAccountingRef`, same interface + storage as `src/PancakeV3FeeAccountingRef.sol`, with a single localized hunk: `feeGrowthGlobal0X128 = deltaX128` (assignment) instead of the canonical `+=` on the `zeroForOne` branch. Mirrors the hyperevm-safety planted-twin convention (the Broken contract lives inline in the test file, not in `src/`, because it is a documented bug-class model).
   - `test_property_planted_zeroForOne_decreasingAmount_invariantViolated`, fixed-input boundary witness (`amount1=1e24`, `amount2=1e22`) that produces a strict decrease and logs + reverts with `INVARIANT VIOLATED feeGrowth_neverDecreases`.
   - `testFuzz_property_planted_zeroForOne_decreasingAmount_invariantViolated`, fuzz sweep over `(a1, a2)` with `a1 > a2 ≥ 2000`; the planted bug always surfaces.

   The CI's `p1-feegrowth-clean-passes` + `p1-feegrowth-planted-fires` jobs were already wired in Week 1 with a file-presence gate (`invariants/planted/PancakeV3FeeGrowth.planted.t.sol`). Both jobs flip automatically from `deferred` to `real-work-green` the moment the planted file lands. No edits to `.github/workflows/ci.yml` were needed.

2. **P-4 LiquidityEventConsistency.** New files: `src/PancakeV3LiquidityEventsRef.sol` + `invariants/PancakeV3LiquidityEvents.t.sol`. The reference exposes `mint`, `burn`, and `crossTick`; the property asserts `liquidity_after - liquidity_before == ±amount` for in-range positions and `== 0` for out-of-range, plus a stateful-fuzz invariant comparing active liquidity against a net-mint-minus-burn shadow under a clamped tick band. Eight tests, all green.

3. **P-5 FeeGrowthOutsideConsistency.** New files: `src/PancakeV3FeeGrowthOutsideRef.sol` + `invariants/PancakeV3FeeGrowthOutside.t.sol`. The reference models the per-tick `feeGrowthOutside0/1X128` state plus the canonical Uniswap v3 init + flip rules; the property asserts `feeGrowthOutside[t] ≤ feeGrowthGlobal` (the increment-only conservation form, wrap-around modelling is an honest documented gap). Seven tests, all green, including a 6-tick stateful-fuzz invariant under accrue + cross fuzzing.

Updated: `SCOPE.md` (flipped P-4, P-5, P-1-planted-twin from ⬜ M2 to ✅ M2; added Week-2 rationale paragraph) and this `RUN_SUMMARY.md`. `docs/invariants.md` continues to list P-4, P-5, the in-code NatSpec is the precise mechanical statement; the prose doc gets a Week-2 update in §W2-7 below.

## §W2-2. What is still M2 / M3 / not-started

Per the updated `SCOPE.md` §1:

- **M2 (Week 3+ planned):** P-6 ProtocolFeeAccrualBound, P-7 ObservationCardinalityMonotonicity, planted-twin CI pairs for P-2 + P-3, P-5 wrap-around variant, BSC-mainnet fork tests against a real PancakeSwap v3 pool at a pinned block, Recon Chimera `Properties.sol` + `CryticTester.sol` scaffold. **Not started.**
- **M2 (out of Week-2 scope per dispatch):** Venus lending invariants V-1 / V-2 / V-3 / V-4. **Not started.**
- **M3 (out of Week-2 scope per dispatch):** Stargate-on-BSC bridge invariants S-1 / S-2 / S-3 + BNB Chain AI agent-registry harness A-1 / A-2. **Not started.**

The Venus + Stargate + agent-registry surfaces remain untouched. CI's path-gated placeholder jobs continue to emit `::notice::` lines until those harnesses land.

## §W2-3. CI status (from logs, not the badge)

Repo is still private; no remote push yet. The local proof is the four log files in `receipts/`. Summary:

- **`receipts/forge-build-2026-06-27-week2.log`**, `forge build` clean (compiler run successful + advisory `unsafe-typecast` / `mixed-case-function` lints; identical class to Week 1, see §3).
- **`receipts/forge-test-2026-06-27-week2.log`**, clean leg (`forge test --match-path 'invariants/*.t.sol' --no-match-path 'invariants/planted/*' -vv`). Tail:

  ```
  Ran 4 test suites in 1.32s (3.16s CPU time): 31 tests passed, 0 failed, 0 skipped (31 total tests)
  ```

  **31 / 31 pass**: 16 Week-1 (P-1 + P-2 + P-3) + 8 P-4 + 7 P-5 = 31 across 4 suites. 4 stateful-fuzz invariants (256 runs × 50 depth = 12,800 calls each, 0 reverts).

- **`receipts/planted_demo/p1-clean-passes-2026-06-27.log`**, clean leg for the P-1 planted-twin gate (`forge test --match-path 'invariants/PancakeV3FeeGrowth.t.sol' -vv`). Exit 0. 5/5 pass. 0 `INVARIANT VIOLATED` markers in stdout. ✓
- **`receipts/planted_demo/p1-planted-fires-2026-06-27.log`**, planted leg (`forge test --match-path 'invariants/planted/PancakeV3FeeGrowth.planted.t.sol' -vv`). Exit 1. 2/2 fail. 5 `INVARIANT VIOLATED feeGrowth_neverDecreases` markers in stdout. ✓

Both CI invariants the `p1-feegrowth-*` jobs gate on are satisfied:

- Clean leg: exit 0 AND no `INVARIANT VIOLATED` marker present → `p1-feegrowth-clean-passes` job passes.
- Planted leg: non-zero exit AND `INVARIANT VIOLATED` marker present → `p1-feegrowth-planted-fires` job passes.

CI-on-GitHub status (once the repo lands on a remote and a push runs): `library-build` + `library-properties-clean` mirror the local pass; `p1-feegrowth-clean-passes` + `p1-feegrowth-planted-fires` flip from `deferred` to green automatically (the file-presence gate is satisfied by the new planted file); the three remaining M2/M3 path-gated jobs (Venus, Stargate, plus future P-2/P-3 planted twins) continue to emit `::notice:: ... deferred` lines.

## §W2-4. Files written / changed

```
experiments/bsc-invariants/
  .gitignore                                                     MODIFIED (re-include receipts/**/*.log so they're committable)
  SCOPE.md                                                       MODIFIED (P-4/P-5/P-1-planted → ✅; Week-2 rationale)
  RUN_SUMMARY.md                                                 MODIFIED (Week-2 sections appended)
  docs/invariants.md                                             MODIFIED (P-4 + P-5 prose added; P-1 planted-twin marked LANDED)
  src/PancakeV3LiquidityEventsRef.sol                            NEW
  src/PancakeV3FeeGrowthOutsideRef.sol                           NEW
  invariants/PancakeV3LiquidityEvents.t.sol                      NEW
  invariants/PancakeV3FeeGrowthOutside.t.sol                     NEW
  invariants/planted/PancakeV3FeeGrowth.planted.t.sol            NEW
  receipts/forge-build-2026-06-27-week2.log                      NEW
  receipts/forge-test-2026-06-27-week2.log                       NEW
  receipts/planted_demo/p1-clean-passes-2026-06-27.log           NEW
  receipts/planted_demo/p1-planted-fires-2026-06-27.log          NEW
```

**`.gitignore` note.** The repo-root `.gitignore` ignores `*.log` globally, a sensible default for Foundry build noise. Receipts under `experiments/bsc-invariants/receipts/` ARE dispatch deliverables (per `T-bnb-bsc-invariants-week2-2026-06-27` "receipts committed at `receipts/planted_demo/`"), so the local `.gitignore` re-includes them with `!receipts/**/*.log`. This fix retroactively makes Week-1's existing `receipts/forge-{build,test}-2026-06-27.log` committable as well (they were generated in Week 1 but `*.log`-ignored, an oversight from Week 1 that this change resolves).

No other paths in the repo touched. No `git add -A`; the Build Engineer / Director will scope the commit set deliberately per dispatch discipline ("Do NOT run git commit"). Existing Week-1 files unchanged except `SCOPE.md` + `RUN_SUMMARY.md`.

**Secret-scan note.** No `.env`, credentials, or tokens written. `.gitignore` already excludes `lib/`, `out/`, `cache/`, no wholesale vendoring; no new entries needed.

## §W2-5. Receipts & reproduction

```bash
cd experiments/bsc-invariants
# Build:
forge build
# Clean leg (Week 1 + Week 2):
forge test --match-path 'invariants/*.t.sol' \
  --no-match-path 'invariants/planted/*' -vv
# Planted leg (must exit non-zero and surface "INVARIANT VIOLATED ..."):
forge test --match-path 'invariants/planted/PancakeV3FeeGrowth.planted.t.sol' -vv
```

Provenance: tested against `lib/forge-std @ v1.9.4` (tag `1eea5bae12ae557d589f9f0f0edae2faa47cb262`) on Foundry `1.7.1` (commit `4072e48705af9d93e3c0f6e29e93b5e9a40caed8`), solc 0.8.28, on macOS arm64 (operator host) at 2026-06-27.

## §W2-6. Known gaps + Week 3 plan

**Honest gaps in v0.0.2:**

1. **P-5 is the increment-only conservation form**, `feeGrowthOutside[t] ≤ feeGrowthGlobal`. Real Uniswap v3 stores both as `uint256` with wrap; the `(global - outside)` subtraction recovers position-local growth modulo 2^256. The wrap-around variant of P-5 is M2 work for Week 3 and is documented as a gap in `src/PancakeV3FeeGrowthOutsideRef.sol` NatSpec + `docs/invariants.md` P-5 § "What this models".
2. **P-5 cross walks only the destination tick**, real v3 walks all initialized ticks strictly between current and `newTick`. The minimal reference is sufficient to exercise the flip rule and the conservation property; the multi-cross walk is a Week-3 add and is called out in the reference's NatSpec.
3. **Planted-twin CI pairs only land for P-1**, P-2 (TickInBounds) and P-3 (SqrtPriceX96InBounds) planted twins are Week-3 work. The CI's `library-properties-clean` job already covers the clean legs for all three; the planted-twin discipline scales as a Week-3 add.
4. **No BSC-mainnet fork tests yet.** Lands at M2 Week 3, the highest-value remaining add for the grant narrative ("tested against PancakeSwap v3 at BSC block N" beats "tested against a reference").
5. **No Recon Chimera bundle yet.** Lands at M2 Week 3 alongside the wrap-around P-5 variant.

**Week-3 plan** (per `bnb_grant_win_analysis_2026-06-26.md` §4.2 B6 + the Week-2 dispatch's "after this lands, Director queues the §4b read"):

- Ship P-6 ProtocolFeeAccrualBound + P-7 ObservationCardinalityMonotonicity.
- Land planted-twin CI pairs for P-2 and P-3.
- Add the first BSC-mainnet fork test against a real PancakeSwap v3 pool at a pinned block.
- Land the wrap-around variant of P-5.
- Pull the §4b `code_quality_reviewer` independent read on what Weeks 1+2 shipped, BEFORE any public flip discussion with the CEO.

## §W2-7. Discipline checklist

- [x] No `git commit` run (Director/Build Engineer commits after review)
- [x] No `git add -A`; file list above is scoped
- [x] No secrets / `.env` / credentials in any written file
- [x] CI status reported from logs, not from a (non-existent) badge
- [x] Repo still private; no public flip (§4b + CEO gates remain queued)
- [x] No nested sub-agents spawned
- [x] No wholesale vendoring; `.gitignore` excludes `lib/` `out/` `cache/`
- [x] Born-with-license preserved; Apache-2.0 SPDX header on every new `.sol` file
- [x] README + SCOPE claim only what is in-tree at HEAD, P-4 / P-5 / P-1-planted flipped to ✅ only because tests pass; P-5's increment-only-conservation scope is documented as a gap
- [x] Planted twin lives inline in the test file (hyperevm-safety convention), not in `src/`
- [x] One-line receipt to Director will be written to `agents/solidity_specialist/outbox/`

## §W2-8. Decision queued for CEO

None new from this dispatch. The Week-1-carried `D-bnb-grant-ask-band-2026-06-26` (ratify $80K mid-band ask) remains the only standing CEO call.

**Operational hand-off (Director-level, not CEO):** the §4b independent `code_quality_reviewer` read on Weeks 1+2 is now appropriate to queue. The reviewer must NOT be the solidity_specialist that built this; the audit runs against `agents/ai_ops/policies/code_authoring_standard.md`. The public flip remains CEO-gated and additionally blocked on the Chrome/Playwright form walk per `bnb_grant_win_analysis_2026-06-26.md` §10.
