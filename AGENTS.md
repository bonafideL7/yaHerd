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

## 2. Keep implementation scope intentional

Change only files required by the design.

Do not introduce unrelated cleanup, new abstractions, new state mechanisms, or new persistence/synchronization behavior unless required for correctness.

If implementation begins expanding because earlier changes created new problems, stop editing and reassess the design before adding more fixes.

A review comment that reveals a missed production path, persistence/synchronization flaw, concurrency flaw, or incorrect ownership/state model requires a design reassessment of the affected feature, not another isolated patch.

## 3. Test behavior, not review comments

Tests exist to protect stable behavior and important invariants.

Add or update tests when needed for the implementation, but do not execute test or verification commands unless the user explicitly asks for them.

Do not create a new test file or permanent global verification entry for every review comment.

Prefer extending an existing behavioral test suite when the behavior belongs there.

Do not add duplicate tests that exercise the same invariant through slightly different fixtures unless they protect a materially different production path.

Feature-specific regression tests must remain ordinary test-target tests unless they protect a repository-wide invariant. Do not append feature-specific suites to `Scripts/verify-concurrency.sh`.

## 4. Verification execution policy

Do not run verification scripts, test commands, build commands, lint commands, or GitHub Actions verification unless the user explicitly requests verification in the current conversation.

In particular, do not run:

```sh
bash Scripts/verify-architecture.sh
bash Scripts/verify-concurrency.sh
```

Do not trigger, re-run, dispatch, or modify CI for the purpose of obtaining verification results unless the user explicitly requests it.

Code review and self-review must use repository inspection, call-path tracing, diff inspection, and static reasoning unless the user explicitly authorizes command execution.

A lack of executed verification is expected under this policy and must not by itself cause another verification run.

## 5. Self-review before push

Before pushing a completed change:

1. Inspect the full diff against the PR base.
2. Trace affected production callers and mutation paths again.
3. Look specifically for missed paths, duplicated logic, unnecessary abstractions, stale code, persistence/sync divergence, races, and missing failure handling.
4. Fix material findings.
5. Review the corrected full diff again.

Do not run tests or verification as part of this self-review unless the user explicitly requests it.

GitHub review is the independent final check, not the mechanism used to discover basic implementation completeness.

## 6. Delivery

Every delivery must report:

- behavior implemented
- files changed
- affected production paths reviewed
- tests added or updated
- verification status, normally `not run by user instruction`
- material self-review findings corrected
- remaining unverified behavior or risk

Do not describe verification as passed unless the requested command was actually run and passed.