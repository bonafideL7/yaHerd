# yaHerd Engineering and Code Review Instructions

These instructions guide Codex implementation and code review. They do not require separate planning, tracking, or verification artifacts.

## Source of truth

- User requirements determine intended behavior. The current production code is the authority for how the application is implemented.
- Inspect the current source and affected execution paths before proposing changes or review findings.
- Do not treat historical assistant-generated plans, documentation, matrices, or prior decisions as requirements.
- Reevaluate previously implemented designs when a defect or review finding exposes a better explanation or simpler correction.

## Implementation

Before changing production code:

- Trace the actual affected views, use cases, repositories, callers, and mutation/read paths.
- Identify the root cause and the smallest correct design, including relevant persistence, navigation, concurrency, accessibility, recovery, and cross-feature effects.
- Reuse existing components and architecture where appropriate; do not duplicate implementations or add unrelated abstractions.
- Fix production behavior, not test expectations, verification output, or a narrowly worded review comment.
- If a fix grows into repeated workarounds, reassess the design rather than stacking patches.
- Do not modify unrelated features or restore files or infrastructure intentionally removed by the user.

Do not create Markdown documentation, dependency or navigation matrices, implementation trackers, automated tests, test targets, or CI workflows unless the user explicitly requests them. This file is retained to guide Codex reviews; it is not an instruction to generate more documentation.

## Persistence direction

yaHerd uses a local-only Core Data `NSPersistentContainer`. The app is prelaunch and does not require a SwiftData migration, compatibility layer, or dual-write path.

- Do not reintroduce SwiftData production repositories, models, migration adapters, or supporting infrastructure.
- Do not treat historical SwiftData implementation or historical planning documents as the active architecture.
- Preserve data integrity, object identity, relationship behavior, history, and Core Data recovery paths when they are affected by a change.

## Codex code review

Review the **actual diff and affected production execution paths**, not documentation or imagined test coverage. Inspect all materially affected callers and the consequences of the proposed implementation, including relevant:

- Success, failure, rollback, and recovery paths.
- Current-state and persisted-state reload behavior.
- Lists, details, dashboards, counts, filters, and other consumers of changed data.
- Relationships, history, identities, ordering, timestamps, and cross-feature interactions.
- Races, stale state, resource handling, privacy, security, and crash risks.

The review must identify **concrete production defects** with an actionable explanation: affected code path, triggering conditions, expected versus actual behavior, and impact. Do not submit speculative findings or require a new document, matrix, or test as proof of a defect.

Treat a finding as blocking only when it has a credible production impact such as broken functionality, incorrect persisted data or state transitions, data loss, a crash, security/privacy exposure, or a material concurrency or recovery defect. Severity must follow from impact, not from the existence of a missing artifact or an untested permutation.

Review the full affected scope and report identifiable material findings together. Do not intentionally issue one sibling edge case per review round or demand duplicate implementations for equivalent input permutations. An empty review is appropriate when no material defect is found.

### Reviewing fixes

- Verify that the reported defect was corrected in production code, not just that a test or check now passes.
- Inspect the new diff and any paths it actually affects for regressions.
- Reopen otherwise unchanged code only when there is concrete evidence of a broader root cause.
- If a fix reveals a category-wide defect, identify the full applicable category in the same review.
- Do not restart an unlimited review cycle or introduce unrelated improvements during defect correction.
- After repeated review cycles without convergence, reassess the underlying design or review assumptions instead of manufacturing additional work.

## Verification and delivery

- Use available build tools and direct source inspection to verify production changes; validate runtime behavior when the environment supports it.
- Do not recreate or modify tests or CI to obtain a passing result.
- A successful build is not proof that reported runtime behavior was fixed.
- Do not claim to have executed builds or verified behavior when that was not done.
- Before submitting a PR, inspect the final diff for unrelated changes, duplicate logic, unnecessary complexity, and accidentally restored files.
- Report what changed, the root cause where applicable, the production paths inspected, verification actually performed, and remaining limitations.
