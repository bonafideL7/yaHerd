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

Review the complete diff against the matrix in one pass. A finding should identify a concrete defect, an incorrect matrix cell, or a materially distinct missing production path/invariant. Do not add findings solely for additional permutations of behavior already represented by the same production path and invariant. On re-review, verify prior fixes and changed code; do not restart an unrestricted edge-case search in unchanged code unless a fix demonstrates a broader category-level flaw.