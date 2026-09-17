## Summary

<!-- Describe the behavior changed and why. -->

## Behavioral ownership

### Owned by this PR

- 

### Existing contract owners reused

- 

### Delegated / owned elsewhere

- 

### Dependencies

- 

### Explicitly out of scope

- 

## Comprehensive behavioral coverage matrix

<!--
Create the matrix before implementation. Add one row per materially distinct production behavior, not one row per review comment or fixture permutation.

Use: Covered / N/A / Delegated: <owner> / Unverified: <reason>
Add detail below the table when a cell cannot be explained briefly.
-->

| Production behavior | Production callers | Success | Error / rollback | Clear / reset | Batch / mixed input | Same context | Fresh reload | Read projections | Relationships / history | Cross-feature effects | Unrelated controls | Identity / metadata | Contract owner |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |  |  |  |  |  |  |  | This PR |

## Matrix notes

<!-- Record important N/A decisions, delegated ownership, representative-case rationale, or persistence-neutral contracts awaiting Core Data integration. -->

- 

## Production paths reviewed

- 

## Production read projections reviewed

- 

## Tests / contracts changed

- 

## Self-review findings corrected

- 

## Verification

- Status: not run by user instruction
- Commands run: none

## Remaining risk / unverified behavior

- 

## Review instructions

Review the complete diff against the complete matrix in one pass and report all currently identifiable material findings together.

A finding must identify a concrete defect, an incorrect matrix cell, or a materially distinct missing production path/invariant. Do not add findings solely for additional fixture permutations, identifier combinations, ordering examples, adjacent assertions, speculative hardening, or future architecture improvements when the same production path and invariant are already represented.

Before raising any cross-feature or cross-PR finding, verify the ownership/delegation sections above and any referenced permanent contract owner. Do not request duplicate implementation or coverage for behavior owned elsewhere unless this PR directly changes that behavior or the ownership declaration is demonstrably incorrect.

Blocking/P1/P2 findings require a concrete material production impact such as a regression, data-integrity/persistence risk, materially uncovered production path or invariant, failure/recovery defect, crash, concurrency defect, security/privacy issue, or user-data-loss risk. A severity label alone does not make a finding blocking.

On re-review, verify prior fixes and changed code; do not restart an unrestricted edge-case search in unchanged code unless a fix demonstrates a broader category-level flaw. If a broader flaw is exposed, report the complete identifiable category in that review rather than one sibling case at a time.

After two corrective review cycles, any new finding in unchanged or previously reviewed behavior must identify the wrong/missing matrix row or cell, explain why it is materially distinct, explain why it could not reasonably have been identified in the prior comprehensive review, and state the concrete production impact if blocking. Otherwise it is non-blocking.

Repeated non-convergence after two corrective cycles is a scope, design, ownership, or instruction problem. Resolve that underlying problem before continuing ordinary code review.

If no material finding meets these rules, return a clean review. Zero findings is the expected successful stopping condition.