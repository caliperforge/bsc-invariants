# AI Disclosure: bsc-invariants

The `bsc-invariants` library is built and maintained by CaliperForge
under an AI-augmented authoring stack. This document is calm
disclosure of which surfaces are AI-touched and the review discipline
that gates each one. The discipline mirrors the sibling library
`hyperevm-safety`.

## What is AI-touched

- **Invariant proposals.** Candidate invariant predicates (the property
  prose, the Solidity property body) are drafted by a Claude model
  and reviewed and edited by the case specialist (`solidity_specialist`)
  before being committed. Upstream v3-core math constants are
  reproduced 1:1 from the published Uniswap v3 source (the constants
  are facts, not generated).
- **Reference contracts.** The minimal reference under
  `src/PancakeV3FeeAccountingRef.sol` is a same-source twin minimal to
  the invariants under test. It is NOT a fork of PancakeSwap's
  production source; the upstream pool source is at
  `pancakeswap/pancake-v3-contracts` (GPL-2.0-or-later) and is
  referenced via attribution in `NOTICE`, not vendored.
- **READMEs and case write-ups.** Drafted with AI assistance;
  reviewed against CaliperForge's internal anti-AI-ism and register
  rubric before publish.

## What is NOT AI-touched

- The published v3 whitepaper / Uniswap v3 core source the invariants
  cite (carried as-cited).
- The CI verdict (pass / fail is a function of the `forge` run, not
  the model).
- The operator-approved positioning paragraph (README.md §1): operator-authored, AI copy-edited 2026-06-27 (em-dash and generic-vocab sweep authorized by CEO 2026-06-27 per the §4a anti-AI-ism pass), operator-approved. The text remains the operator-locked positioning across surfaces; the 2026-06-27 sweep modified only typography (em-dash → colon) and one generic-adjective replacement (comprehensive → broad).
- The operator's final-pass sign-off decisions and the milestone
  exit-gate sign-offs.

## Audit trail

- Every commit lists the author (Michael Moffett, operator at
  CaliperForge) and is operator-clean (no `Co-Authored-By` trailers).
- The library-build + library-properties CI legs are uploaded as
  artifacts on every push (see `.github/workflows/ci.yml`).
- Code-quality reviewer audit per CaliperForge §4b runs BEFORE any
  public flip; this repo is private until §4b PASS + CEO greenlight.

## Why we disclose

CaliperForge's identity register makes AI-augmented authorship the
default disclosure posture, not the exception. Reviewers should know
which content was AI-drafted so they can apply their own scrutiny at
that surface. See
[caliperforge.com/ai-disclosure](https://caliperforge.com/ai-disclosure)
for the org-level register.

## Contact

Operator: Michael Moffett, michael@caliperforge.com, team@caliperforge.com.
