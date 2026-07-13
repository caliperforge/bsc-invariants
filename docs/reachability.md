# Multi-seed reachability certification

## What this fixes

The base per-invariant `planted-fires` job in `.github/workflows/ci.yml`
runs each planted twin once per commit with whatever fuzz seed CI
happens to draw. Deterministic witnesses fire reliably, but a lucky
CI seed on a longer or rarer trigger for the fuzz variants would leave
a false green where the docs claim a hard red.

The multi-seed reachability leg (`ci/reachability_leg.sh`) closes that
gap for every active planted twin: it runs each twin's suite once per
seed across a fixed 16-seed set (`ci/reachability_seeds.txt`) and
requires every seed to produce at least one `INVARIANT VIOLATED` marker
and a non-zero forge exit. If any seed passes on any twin, the leg
fails and the docs' k / 16 number for that twin goes down instead of
quietly staying at 16 / 16.

## Verdict (per active twin)

Recorded from the local run on 2026-07-13 at the current per-twin
budget (each twin's `foundry.toml` `[invariant]` block; standing budget
runs = 256, depth = 50).

| twin | file | k / 16 | verdict |
| --- | --- | --- | --- |
| P-1 PancakeV3FeeGrowth | `invariants/planted/PancakeV3FeeGrowth.planted.t.sol` | 16 / 16 | reachability certified: yes (16/16 failed as required) |

Overall:

```
reachability certified: yes (all active twins, 16/16 failed as required)
```

## Not yet in scope

M2 (Venus) and M3 (Stargate-on-BSC) harnesses are still path-gated
placeholders in the base CI. The reachability leg extends by three
lines (label + gate + cmd) per new twin the same commit each lands.

## Merge-gate rule

No new planted twin merges to `main` unless the reachability leg exits
green (fail-on-all-N) for that twin. If a new twin cannot certify at
its default budget, the case owner:

1. Bumps `[invariant] runs` or `depth` in the case's `foundry.toml`
   until the leg certifies, OR
2. Documents an honest caveat in the case README stating the k / N
   number the twin currently achieves at the standing budget.

The reachability leg is wired as a required check in
`.github/workflows/ci.yml` (`reachability-multi-seed` job).

## Seed set

The seed list is a fixed, deterministic mix of small integers, common
test patterns, and pseudo-random-looking bytes. It is not regenerated
per run. See `ci/reachability_seeds.txt`.

## Reuse

The canonical script this leg mirrors lives at
`scripts/reachability/run_foundry_reachability.sh` in the
`caliperforge/crypto-contributor` repo. Future twins lift that script
and the seed set verbatim.
