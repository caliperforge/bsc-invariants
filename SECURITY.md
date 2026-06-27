# Security Policy: bsc-invariants

## Scope

`bsc-invariants` is an open-source library of Foundry property tests
for BNB Smart Chain DeFi protocols. The repo ships **invariants and
test scaffolding**, not deployable contracts. The `src/` reference
contracts (`PancakeV3FeeAccountingRef.sol`, etc.) are minimal twins
authored for invariant testing and are not meant to be deployed to
mainnet.

## Reporting a vulnerability

If you find an issue in the *invariant predicates themselves* (e.g.,
an invariant that misses a documented bug class, or a property whose
implementation diverges from the upstream v3 statement it cites),
please open a GitHub issue or contact CaliperForge at
`security@caliperforge.com`.

If you find a vulnerability in a deployed BSC protocol (PancakeSwap,
Venus, Stargate, etc.) while using or extending this library, please
report it via the affected protocol's own bug-bounty program (Immunefi,
the project's HackerOne, etc.) and NOT to this repo. We will gladly
help triage but cannot accept reports of third-party protocol issues
here.

## Not in scope

- Operational security of upstream protocols. `bsc-invariants` does
  not certify any protocol; see the "What this library does NOT
  claim" section of `README.md`.
- Runtime monitoring or alerting. The properties are pre-deploy CI
  gates, not on-chain monitors.

## Disclosure timeline

CaliperForge follows a coordinated-disclosure norm: 90-day default,
extendable by mutual agreement with the affected upstream when fixes
require longer windows.
