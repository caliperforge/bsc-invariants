#!/usr/bin/env bash
# Multi-seed reachability leg for bsc-invariants planted twins.
#
# For each active planted twin, runs the twin's test suite once per seed
# in ci/reachability_seeds.txt (N=16 by default). Every (twin, seed)
# pair must exit non-zero AND print at least one `INVARIANT VIOLATED`
# marker. This upgrades the base planted-fires legs' single-seed catches
# to a deterministic N-of-N certification per twin: no false-green from
# a lucky CI seed.
#
# Active planted twins as of 2026-07-13 (path-gated in .github/workflows/ci.yml):
#
#   - invariants/planted/PancakeV3FeeGrowth.planted.t.sol
#       (P-1 PancakeSwap v3 fee-growth monotonicity, fuzz + deterministic)
#
# New twins land as three lines below (label + gate + cmd).
#
# Emits per-(twin, seed) lines and, per twin, a single verdict, and an
# overall verdict at the end that is green only when every active twin
# certifies fail-on-all-N.
#
# See ../scripts/reachability/ in the caliperforge crypto-contributor
# repo for the canonical runner this mirrors.

set -uo pipefail

summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
seeds_file="${SEEDS_FILE:-ci/reachability_seeds.txt}"

if [ ! -f "$seeds_file" ]; then
  echo "reachability-multi-seed: seeds file not found: $seeds_file" >&2
  exit 2
fi

seeds=$(grep -vE '^\s*(#|$)' "$seeds_file")

declare -a labels=(
  "P-1 PancakeV3FeeGrowth"
)
declare -a gates=(
  "invariants/planted/PancakeV3FeeGrowth.planted.t.sol"
)
declare -a cmds=(
  "forge test --match-path 'invariants/planted/PancakeV3FeeGrowth.planted.t.sol' --fuzz-seed %s -vv"
)

{
  echo "## Multi-seed reachability (16 seeds per twin)"
  echo ""
} >>"$summary"

overall_rc=0

for i in "${!labels[@]}"; do
  label="${labels[$i]}"
  gate="${gates[$i]}"
  cmd_fmt="${cmds[$i]}"

  if [ ! -f "$gate" ]; then
    msg="$label: gate file $gate missing; twin not yet landed. Skipping."
    echo "$msg"
    echo "$msg" >>"$summary"
    continue
  fi

  total=0
  failed=0
  missed=""

  {
    echo "### $label"
    echo ""
    echo "| seed | outcome | markers |"
    echo "| --- | --- | --- |"
  } >>"$summary"

  for seed in $seeds; do
    total=$((total + 1))
    cmd=$(printf "$cmd_fmt" "$seed")
    out=$(bash -c "$cmd" 2>&1)
    rc=$?
    markers=$(printf '%s\n' "$out" | grep -c "INVARIANT VIOLATED" || true)

    if [ "$rc" -ne 0 ] && [ "$markers" -gt 0 ]; then
      echo "$label seed $seed: FAILED as required (rc=$rc, markers=$markers)"
      echo "| \`$seed\` | failed (required) | $markers |" >>"$summary"
      failed=$((failed + 1))
    elif [ "$rc" -eq 0 ]; then
      echo "$label seed $seed: passed unexpectedly (rc=0). planted-twin escaped on this seed."
      echo "| \`$seed\` | ESCAPED (rc=0) | 0 |" >>"$summary"
      missed="$missed $seed"
    else
      echo "$label seed $seed: rc=$rc but no INVARIANT VIOLATED marker; treating as escape."
      echo "| \`$seed\` | escape (no marker, rc=$rc) | 0 |" >>"$summary"
      printf '%s\n' "$out" | tail -20
      missed="$missed $seed"
    fi
  done

  if [ "$failed" -eq "$total" ]; then
    verdict="$label reachability certified: yes ($failed/$total failed as required)"
    echo "$verdict"
    echo "" >>"$summary"
    echo "**$verdict**" >>"$summary"
  else
    verdict="$label reachability certified: no ($failed/$total failed; missed on seeds:$missed)"
    echo "$verdict"
    echo "" >>"$summary"
    echo "**$verdict**" >>"$summary"
    overall_rc=1
  fi
done

echo ""
if [ "$overall_rc" -eq 0 ]; then
  echo "reachability certified: yes (all active twins, 16/16 failed as required)"
  echo "" >>"$summary"
  echo "**reachability certified: yes (all active twins, 16/16 failed as required)**" >>"$summary"
else
  echo "reachability certified: no (at least one twin missed; see per-twin lines above)"
  echo "" >>"$summary"
  echo "**reachability certified: no (see per-twin lines above)**" >>"$summary"
fi

exit "$overall_rc"
