# bsc-invariants — RUN_SUMMARY (Week 1, 2026-06-27)

**Repo target:** `experiments/bsc-invariants/` (will land at `github.com/caliperforge/bsc-invariants` on the public flip — gated on §4b code-quality reviewer PASS + CEO greenlight).
**Owner:** Solidity Specialist.
**Dispatch:** `T-bnb-bsc-invariants-week1-2026-06-27` (Director, per CEO greenlight `D-bnb-grant-greenlight-2026-06-27`).
**Source pattern (port-from):** `experiments/hyperevm-safety/` — Foundry harness + planted-twin discipline + path-gated CI.
**Scope source:** `agents/research_lead/outbox/bnb_grant_win_analysis_2026-06-26.md` §3.2.

---

## §1 — What shipped (Week 1)

The minimal-winning-build §3.2 elements B2 + B3 + SCOPE table:

1. **Repo scaffold.** `experiments/bsc-invariants/` with the born-with-license discipline (Apache-2.0 `LICENSE` + `NOTICE` from commit one). Files: `README.md`, `LICENSE`, `NOTICE`, `AI_DISCLOSURE.md`, `SECURITY.md`, `SCOPE.md`, `.gitignore`, `foundry.toml`, `remappings.txt`.
2. **CI wiring.** `.github/workflows/ci.yml` mirrors the `hyperevm-safety` pattern — `library-build` + `library-properties-clean` for M1, plus four path-gated jobs for M2 / M3 (P-1 planted-twin clean leg + planted leg, Venus harness build, Stargate harness build). Each future job flips from `deferred` to `real-work-green` the moment its wiring file lands. Composite Foundry-setup action at `.github/actions/foundry-setup/`.
3. **PancakeSwap v3 invariant harness v0.**
   - `src/lib/TickMath.sol` — Uniswap v3 / PancakeSwap v3 address-space constants (MIN_TICK = -887272, MAX_TICK = 887272, MIN_SQRT_RATIO = 4295128739, MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342). Attribution in `NOTICE` (constants are facts; implementations not reproduced).
   - `src/PancakeV3FeeAccountingRef.sol` — minimal same-source reference modelling the v3 fee-growth `+=` update, the tick + sqrtPriceX96 state, and bound-enforcing `require` checks.
   - `invariants/PancakeV3FeeGrowth.t.sol` — **P-1 FeeGrowthGlobalMonotonicity** with one stateful-fuzz invariant (`invariant_feeGrowth_neverDecreases`) + 4 unit/fuzz property tests + a bounded handler so the fuzzer hits in-bound inputs.
   - `invariants/PancakeV3TickBounds.t.sol` — **P-2 TickInBounds** (5 tests) + **P-3 SqrtPriceX96InBounds** (5 tests + 1 fuzz).
4. **SCOPE.md surface table.** Protocols × invariants × status × milestone — single source of truth for what is in-tree vs M2 / M3 / not-started. README + RUN_SUMMARY must not exceed this table.
5. **`docs/invariants.md`** — prose statement + bug-class + upstream citation per invariant.

Week-1 acceptance criterion ("at least one invariant compiling + running under `forge test` by end of Week 1") **PASSES** — 16 tests across 2 suites, all green; see §3.

## §2 — What is M2 / M3 / not-started

Per `SCOPE.md` §1:

- **M2 (Week 2 / Week 3, planned):** P-4 LiquidityEventConsistency, P-5 FeeGrowthOutsideConsistency, P-6 ProtocolFeeAccrualBound, P-7 ObservationCardinalityMonotonicity, planted-twin CI pairs for P-1 / P-2 / P-3 (the deterministic `INVARIANT VIOLATED` pattern the CI's `*-planted-fires` jobs gate on), Recon Chimera `Properties.sol` + `CryticTester.sol` scaffold. **Not started.**
- **M2 (out of Week 1 scope per dispatch):** Venus lending invariants V-1 / V-2 / V-3 / V-4. **Not started.**
- **M3 (out of Week 1 scope per dispatch):** Stargate-on-BSC bridge invariants S-1 / S-2 / S-3 + BNB Chain AI agent-registry harness A-1 / A-2. **Not started.**

The Venus + Stargate + agent-registry surfaces are NOT touched. CI carries path-gated placeholder jobs so the graph stays stable when those harnesses land; today those jobs emit `::notice::` lines explaining the deferral.

## §3 — CI status (from log, not the badge)

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

**16 / 16 tests pass** — 1 stateful-fuzz invariant (256 runs × 50 depth = 12,800 calls; 0 reverts), 2 fuzz tests (1000 runs each), 13 unit/boundary tests.

`forge build` is clean (compiler run successful). It emits `unsafe-typecast` and `mixed-case-function` lints on the reference and tests — these are advisory only (the truncations are bound-protected by `require` checks; the mixed-case names are forge-std-style `test_property_*`). They are NOT errors and do not gate the build; we will quiet them in M2 with the documented `forge-lint: disable-next-line` annotations once the surface stabilizes. Full build log at `receipts/forge-build-2026-06-27.log`.

CI-on-GitHub status (once the repo lands on a remote and a push runs): the `library-build` + `library-properties-clean` jobs should mirror the local pass; the four M2/M3 path-gated jobs will emit `::notice:: ... deferred` lines (this is the expected `wired=false` path).

## §4 — Files written / changed

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

## §5 — Receipts & reproduction

- `receipts/forge-build-2026-06-27.log` — full `forge build` output (compiler run successful + advisory lint warnings).
- `receipts/forge-test-2026-06-27.log` — full `forge test -vv` output (16 / 16 pass).

To reproduce locally:

```bash
cd experiments/bsc-invariants
forge install foundry-rs/forge-std@v1.9.4
forge build
forge test -vv
```

Provenance: tested against `lib/forge-std @ v1.9.4` (tag `1eea5bae12ae557d589f9f0f0edae2faa47cb262`) on Foundry `1.7.1` (commit `4072e48705af9d93e3c0f6e29e93b5e9a40caed8`), solc 0.8.28, on macOS arm64 (operator host) at 2026-06-27.

## §6 — Known gaps + Week 2 plan

**Honest gaps in v0.0.1:**

1. **The reference is "increment-only" arithmetic** — real Uniswap v3 / PancakeSwap v3 stores `feeGrowthGlobalXX128` as `uint256` and ALLOWS wrap-around; position-local growth is recovered modulo 2^256 via the `(global - outside)` subtraction. Modelling that wrap is M2 work (P-5 fee-growth-outside consistency). For Week 1, the increment-only reference is the conservative model — P-1 holds on the increment-only reference iff it holds on the wrapping reference under any sequence of inputs that doesn't cross the wrap boundary, which is the operative case for any realistic swap sequence. Documented in `src/PancakeV3FeeAccountingRef.sol` NatSpec + `docs/invariants.md` P-1 § "Test plan."
2. **No planted-twin clean/planted CI pair yet.** Lands at M2. The CI workflow's `p1-feegrowth-clean-passes` + `p1-feegrowth-planted-fires` jobs are already wired and gate on `invariants/planted/PancakeV3FeeGrowth.planted.t.sol`'s file presence; they emit `::notice:: ... deferred` today.
3. **No Recon Chimera bundle yet.** Lands at M2 alongside the planted twins (`invariants/mocks/CryticTester.sol` + `invariants/mocks/Properties.sol`).
4. **Tick math `getSqrtRatioAtTick` implementation not reproduced.** Only the bound constants are needed for the M1 invariants; if M2 invariants need the function body (P-5 likely will, for cross-tick fee-growth fragment accounting), we either vendor the upstream GPL file with its full header + re-evaluate the repo's license posture, OR link upstream as a git submodule. Decision deferred to the M2 design step (`SCOPE.md` §3).
5. **No fork tests against deployed PancakeSwap v3 mainnet pools.** Lands at M2 — the reference contract proves the invariants on a self-contained twin; the fork test proves the invariants on a real pool at a pinned block. This is the highest-value M2 add for the grant application narrative (lets us claim "tested against PancakeSwap v3 at BSC block X" rather than "tested against a reference").

**Week 2 plan (per `bnb_grant_win_analysis_2026-06-26.md` §4.2 B5 + B6):**

- **B5:** ship P-4 / P-5 / P-6 / P-7 (the remaining PancakeSwap v3 invariants) + the first planted-twin CI pair for P-1.
- **B6:** finish `docs/invariants.md` for all 7 properties + first BSC-mainnet fork test against a real PancakeSwap v3 pool at a pinned block.
- Pull a code_quality_reviewer §4b review on what landed Week 1 + 2 before any public flip is even queued.

## §7 — Discipline checklist

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

## §8 — Decision queued for CEO

None new from this dispatch. Carried forward (from the Research Lead's §5):

- **`D-bnb-grant-ask-band-2026-06-26`** — ratify the $80K mid-band ask (3 deliverables across PancakeSwap v3 + Venus + Stargate + agent-registry). Solidity Specialist surfaces this as the design choice baked into the SCOPE table's milestone partitioning. CEO call.

**Operational decision (Director-level, not CEO):** the §4b code-quality reviewer (`code_quality_reviewer`, NOT the solidity_specialist who built this) must audit the Week 1 + Week 2 scaffold against the `agents/ai_ops/policies/code_authoring_standard.md` ruleset BEFORE any public flip. The §4b review should happen end of Week 2; the public flip is CEO-gated and additionally awaits the Chrome/Playwright form walk (`bnb_grant_win_analysis_2026-06-26.md` §10).
