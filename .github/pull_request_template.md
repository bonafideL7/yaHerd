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
Create the matrix before implementation. Add one row per materially distinct production behavior, not one row per review comment or fixture permutation. The matrix is a living inventory, not a ceiling: if tracing, implementation, or review discovers a materially distinct affected behavior, expand the matrix before addressing it.

Descriptive columns define scope and MUST contain concrete values:
- Production behavior: name the concrete operation/behavior. Never use a status token here.
- Production callers: name the concrete caller(s), use case(s), repository entry point(s), view model(s), or workflow(s). If there is genuinely no production caller, write `None: <reason>` after tracing production code. Never use `Covered`, `N/A`, or another status token as the caller list.
- Contract owner: write `This PR`, a named permanent contract, or a specific PR/work item.

Evaluation columns are Success through Identity / metadata. Each evaluation cell must use one of these forms:
- `Covered: <specific evidence/path/contract>`
- `N/A: <why this dimension does not apply>`
- `Delegated: <specific owner>`
- `Unverified: <specific reason>`

Bare tokens such as `Covered` or `N/A` are invalid because they do not show what was evaluated or why.
Add detail below the table when a cell cannot be explained briefly.
-->

| Production behavior | Production callers | Success | Error / rollback | Clear / reset | Batch / mixed input | Same context | Fresh reload | Read projections | Relationships / history | Cross-feature effects | Unrelated controls | Identity / metadata | Contract owner |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Concrete behavior | Concrete caller(s) | Covered: ... | N/A: ... | N/A: ... | N/A: ... | Covered: ... | Covered: ... | Covered: ... | Covered: ... | Covered: ... | Covered: ... | Covered: ... | This PR |

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

Review the complete diff against the complete matrix, actual affected production call graph, and every affected production read projection in one pass, and report all currently identifiable material findings together. If a materially distinct affected behavior or projection is missing from the matrix, expand the matrix rather than treating the omission as out of scope.

First validate the matrix schema itself. `Production behavior`, `Production callers`, and `Contract owner` are descriptive scope fields and must contain concrete values. Status tokens belong only in evaluation columns, and evaluation cells must include evidence or rationale rather than a bare token. Treat schema ambiguity as one matrix-level finding, not as a sequence of row-by-row comments.

A finding must identify a concrete defect, an incorrect matrix cell, or a materially distinct missing production path/invariant. The matrix must expand for real missing production behavior; it must not be used to suppress such a finding. Do not add findings solely for additional equivalent fixture permutations, identifier combinations, ordering examples, adjacent assertions, speculative hardening, or future architecture improvements when the same production path and invariant are already represented.

Before raising any cross-feature or cross-PR finding, verify the ownership/delegation sections above and any referenced permanent contract owner. Do not request duplicate implementation or coverage for behavior owned elsewhere unless this PR directly changes that behavior or the ownership declaration is demonstrably incorrect.

Blocking/P1/P2 findings require a concrete material production impact such as a regression, data-integrity/persistence risk, materially uncovered production path or invariant, failure/recovery defect, crash, concurrency defect, security/privacy issue, or user-data-loss risk. A severity label alone does not make a finding blocking.

On re-review, verify prior fixes and changed code; do not restart an unrestricted edge-case search in unchanged code unless a fix demonstrates a broader category-level flaw. If a broader flaw is exposed, report the complete identifiable category in that review rather than one sibling case at a time.

After two corrective review cycles, any new finding in unchanged or previously reviewed behavior must identify the wrong/missing matrix row or cell, explain why it is materially distinct, explain why it could not reasonably have been identified in the prior comprehensive review, and state the concrete production impact if blocking. Otherwise it is non-blocking.

Repeated non-convergence after two corrective cycles is a scope, design, ownership, or instruction problem. Resolve that underlying problem before continuing ordinary code review.

If no material finding meets these rules, return a clean review. Zero findings is the expected successful stopping condition.