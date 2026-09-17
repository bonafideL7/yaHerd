# yaHerd Engineering Instructions

These instructions apply to every code change in this repository.

## 1. Design before editing

Before changing production code, inspect the repository and determine the smallest correct design.

For the requested behavior:

- trace every affected production caller and mutation path
- identify persistence, synchronization, concurrency, navigation, UI, accessibility, migration, and recovery boundaries that actually apply
- identify existing behavior that can regress
- define the invariants and failure cases
- identify existing abstractions that should be reused

Do not start by patching the line mentioned in a review comment. Determine the underlying design problem first.

Do not preserve previously generated code merely because it already exists. Replace or revert it when a smaller, clearer implementation is correct.

## 2. Comprehensive behavioral coverage matrix

Every substantive change must begin with a comprehensive behavioral coverage matrix before production code is edited.

The matrix is the finite definition of implementation and review completeness for the PR. It must describe materially distinct production behavior, not individual review comments or every imaginable fixture permutation.

### Required matrix dimensions

For every materially distinct affected production operation or behavior, evaluate all dimensions that actually apply:

| Dimension | Required consideration |
| --- | --- |
| Production operation / behavior | The concrete behavior being changed or preserved |
| Production callers | Every production caller, use case, repository entry point, view model, or workflow that reaches the behavior |
| Success path | Normal mutation or read behavior |
| Error / rollback path | Failure behavior, rollback, recovery, and same-context usability after failure |
| Clear / reset behavior | Optional-field clearing, reset, reopen, undo, or equivalent lifecycle behavior when applicable |
| Batch / mixed-input behavior | Batch operations and mixed valid/missing/stale identifiers when applicable |
| Same-context behavior | Behavior immediately after mutation in the current context when relevant |
| Fresh-context reload | Persisted behavior after re-fetch/reload when persistence is involved |
| Production read projections | Every materially affected list, detail, summary, dashboard, lookup, or derived projection |
| Relationships / history | Relationship integrity, movement/history records, child records, and snapshots |
| Cross-feature effects | Other features that consume or retain the affected state |
| Unrelated control records | Evidence that unrelated entities, sessions, groups, histories, or state remain unchanged |
| Identity / metadata | Stable IDs, timestamps, ordering, status metadata, and other invariants that must survive |
| Contract owner | This PR, an existing permanent contract, or an explicitly identified other PR/work item |

Use `N/A` where a dimension genuinely does not apply. `N/A` is a deliberate decision, not an omitted check.

### Matrix rules

- Rows represent materially distinct production behaviors, not review comments.
- Columns represent behavioral dimensions that must be consciously evaluated.
- Create the matrix before implementation and keep it current as understanding changes.
- Trace production code to populate the matrix; do not infer coverage solely from existing tests.
- Every applicable matrix cell must be implemented and protected by an appropriate existing or new contract, explicitly delegated to another owner, or intentionally documented as unverified when execution is prohibited by these instructions.
- One invariant must have one permanent contract owner. Do not duplicate coverage across PRs merely because the same state appears in multiple features.
- Representative cases are sufficient for equivalent fixture permutations. Do not create Cartesian-product test suites when the same production path and invariant are already exercised.
- A new row is justified only by a materially distinct production path, lifecycle state, persistence boundary, failure mode, read projection, relationship, or invariant.

### When a gap is discovered

When implementation or review exposes a missing behavior:

1. Update the matrix first.
2. Identify the full affected row and any related column/category.
3. Audit all sibling behaviors in that category.
4. Fix the complete category in one change.
5. Update existing behavioral contracts rather than adding one-off review-specific fixtures when possible.

Do not patch only the exact counterexample named by a review comment.

A finding such as "completed Field Check state is lost after pasture deletion" requires an audit of the applicable Field Check lifecycle and persisted payload around pasture deletion, not only one completed-session fixture.

### Matrix completion

A PR is behaviorally complete when:

- every materially distinct affected production behavior appears in the matrix
- every applicable matrix cell is implemented, covered by its declared contract owner, explicitly delegated, or marked `N/A`
- production callers and read projections have been traced against the final implementation
- no material matrix row or cell remains incorrect or unexplained

The matrix is finite. Completeness does not require proving that no additional test input can be imagined.

## 3. Keep implementation scope intentional

Change only files required by the design and coverage matrix.

Do not introduce unrelated cleanup, new abstractions, new state mechanisms, or new persistence/synchronization behavior unless required for correctness.

If implementation begins expanding because earlier changes created new problems, stop editing and reassess the design and matrix before adding more fixes.

A review comment that reveals a missed production path, persistence/synchronization flaw, concurrency flaw, or incorrect ownership/state model requires a design and matrix reassessment of the affected feature, not another isolated patch.

## 4. Persistence direction: Core Data only

yaHerd is replacing SwiftData with Core Data. SwiftData is legacy transitional code scheduled for removal and is not an implementation target for new work.

- Do not add new SwiftData production code, repositories, models, adapters, migrations, fixtures, test runners, or verification infrastructure.
- Do not expand, refactor, or otherwise invest in SwiftData as part of the Core Data migration.
- Existing SwiftData code may be inspected only to understand current behavior that must be preserved during migration.
- New persistence behavior, repositories, migration work, and executable persistence tests must target Core Data, including the planned `NSPersistentCloudKitContainer` architecture, or remain persistence-neutral until the Core Data implementation exists.
- Permanent repository contracts may remain persistence-neutral without an executable runner when the only available runner would require adding or restoring SwiftData-specific code. Wire those contracts into the Core Data test suite when the corresponding Core Data repository is implemented.
- Never satisfy a review comment by adding, restoring, or recommending a SwiftData contract runner solely to execute new persistence-neutral contracts against the legacy implementation.
- During code review, do not report the absence of new SwiftData coverage as a defect when adding that coverage would create temporary SwiftData code. Identify the future Core Data runner as the correct integration point instead.
- Touch existing SwiftData code only when the user explicitly requests a narrowly scoped SwiftData fix or removal step. Do not create new dependencies on SwiftData that will need to be migrated later.

When persistence direction is ambiguous, prefer the Core Data replacement architecture and avoid creating any new SwiftData surface area.

## 5. Test behavior, not review comments

Tests exist to protect stable behavior and important invariants represented by the coverage matrix.

Add or update tests when needed for the implementation, but do not execute test or verification commands unless the user explicitly asks for them.

Do not create a new test file or permanent global verification entry for every review comment.

Prefer extending an existing behavioral test suite when the behavior belongs there.

Do not add duplicate tests that exercise the same invariant through slightly different fixtures unless they protect a materially different production path represented by a separate matrix row.

Do not add another test merely because another valid input permutation can be imagined. Add it only when it exercises a distinct production path, lifecycle state, failure boundary, read projection, relationship, or invariant.

Feature-specific regression tests must remain ordinary test-target tests unless they protect a repository-wide invariant. Do not append feature-specific suites to `Scripts/verify-concurrency.sh`.

## 6. Verification execution policy

Do not run verification scripts, test commands, build commands, lint commands, or GitHub Actions verification unless the user explicitly requests verification in the current conversation.

In particular, do not run:

```sh
bash Scripts/verify-architecture.sh
bash Scripts/verify-concurrency.sh
```

Do not trigger, re-run, dispatch, or modify CI for the purpose of obtaining verification results unless the user explicitly requests it.

Code review and self-review must use repository inspection, call-path tracing, matrix inspection, diff inspection, and static reasoning unless the user explicitly authorizes command execution.

A lack of executed verification is expected under this policy and must not by itself cause another verification run or review finding.

## 7. Self-review before push

Before pushing a completed change:

1. Inspect the full diff against the PR base.
2. Reconcile the final diff against every row and applicable cell in the coverage matrix.
3. Trace affected production callers and mutation paths again.
4. Trace every production read projection listed in the matrix.
5. Look specifically for missed paths, duplicated logic, unnecessary abstractions, stale code, persistence/sync divergence, races, missing failure handling, identity/timestamp/order regressions, and unintended changes to control records.
6. If one defect reveals a category-level omission, audit and fix the entire category before pushing.
7. Review the corrected full diff and matrix again.

Do not run tests or verification as part of this self-review unless the user explicitly requests it.

GitHub review is the independent final check, not the mechanism used to discover basic implementation completeness one counterexample at a time.

## 8. Review convergence

Code review must converge. The goal is to validate the declared behavioral surface, not to generate an unlimited sequence of additional permutations.

### Initial review

Review the complete diff against the complete coverage matrix.

- Inspect the entire declared surface before submitting findings.
- Report all currently identifiable material findings in the same review rather than intentionally stopping after the first few.
- A finding must identify a concrete defect, an incorrect matrix cell, or a materially distinct production path/invariant missing from the matrix.
- Map each behavioral finding to the affected matrix row or identify the new row that is materially required.
- Do not create a finding solely because another fixture permutation, identifier combination, ordering example, or adjacent assertion can be imagined when the same production path and invariant are already covered.
- Do not require duplicate coverage for behavior owned by another declared contract or PR unless the current PR changes that behavior.
- Do not report verification as missing when execution is prohibited by the verification policy.
- Do not require temporary SwiftData infrastructure prohibited by the persistence-direction policy.

If no material finding meets these criteria, return a clean review. A review with zero findings is a successful and expected outcome.

### Re-review after fixes

A re-review is not an unrestricted restart of the entire discovery process.

On re-review:

1. Verify that previous findings were addressed correctly.
2. Inspect code changed since the prior review for regressions or newly introduced defects.
3. Reconcile any changed behavior against the affected matrix rows and columns.
4. Reopen unchanged areas only when a fix provides concrete evidence of a broader design flaw.

If a fix reveals a broader category-level flaw, report the entire identifiable category in one review. Do not expose one sibling case per subsequent review cycle.

Do not repeat an already-decided architecture or ownership disagreement as a new finding. If repository instructions conflict, identify the conflict once as a blocking instruction issue and resolve the instruction/ownership decision before continuing code review.

### Review stopping rule

Review is complete when all prior material findings are resolved and the reviewer cannot identify an incorrect matrix cell or a materially distinct missing production behavior/invariant.

The existence of additional conceivable edge-case inputs is not grounds to continue review.

## 9. Cross-PR and contract ownership

Overlapping PRs must declare ownership explicitly.

Each substantive PR must identify:

- behaviors and invariants owned by this PR
- existing permanent contracts that own related behavior
- behaviors delegated to another named PR/work item
- dependencies on sibling PRs
- intentionally out-of-scope behavior

A behavior must not be repeatedly reimplemented or retested in multiple PRs merely because it is observable from each feature.

When an integration behavior crosses boundaries, assign one owner for the integration contract and reference that owner from the other matrices.

Reviewers must respect declared ownership unless the current PR directly changes the owned behavior or the ownership declaration is demonstrably incorrect.

## 10. Delivery

Every delivery must report:

- behavior implemented
- files changed
- coverage matrix rows added or changed
- affected production paths reviewed
- production read projections reviewed
- tests added or updated
- contract ownership/delegation decisions
- verification status, normally `not run by user instruction`
- material self-review findings corrected
- remaining unverified behavior or risk

Do not describe verification as passed unless the requested command was actually run and passed.