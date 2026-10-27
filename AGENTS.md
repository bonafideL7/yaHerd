# yaHerd Engineering and Code Review Instructions

These instructions guide ChatGPT production implementation and Codex code review. ChatGPT implements production changes and addresses review findings; Codex reviews PRs only and does not implement the feature. They do not require separate planning, tracking, or verification artifacts.

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

## Test-driven implementation and test maintenance

Automated tests are part of normal implementation and defect correction, not optional work deferred until PR verification. ChatGPT is responsible for creating, maintaining, and running tests as needed; Codex remains a reviewer only.

- Before editing production code, inspect relevant existing tests and production call paths. Identify behavior, contracts, invariants, and cross-feature effects at risk. Tests describe intended behavior but do not override current user requirements or actual production behavior.
- For a defect, first write or adjust a focused regression test that demonstrates the defect. For new functionality, define expected success, failure, boundary, and persistence behavior in tests before implementing it. Reuse current fixtures and repository contracts; avoid redundant coverage and unnecessary test scaffolding.
- Implement the smallest correct production change, keeping affected tests and fixtures in sync *during* the change. Interface or model changes must account for affected callers and tests in the same work, not in a subsequent repair PR.
- If an existing test disagrees with changed code, investigate whether the implementation is wrong, the intended behavior changed, or the test is defective. Preserve valid assertions; do not disable, delete, weaken, or skip tests to get a green build.
- Before each implementation commit, review the affected test diff and perform available compilation, targeted test execution, and direct execution-path inspection. Resolve failures before committing when test execution is available. When Xcode/simulators are unavailable locally, explicitly disclose the limitation, use a GitHub-hosted verification run as early as possible in development, inspect its failures, and do not represent unexecuted tests as passing.
- A successful production build or `build-for-testing` does not mean tests executed. Every non-draft PR must run the existing automated test suite on GitHub Actions; a failed, cancelled, or skipped required verification is not acceptable for merging. Keep the required CI check enforced by branch protection.
- Before merging, review the complete diff and require successful CI test execution and appropriate Codex code review. A passing test suite is necessary but not sufficient evidence of correct runtime behavior; perform physical-device or other integration verification where the feature requires it.
- Keep test changes focused on the actual feature or defect; do not restore retired infrastructure or create unrelated process artifacts.

## Persistence direction

yaHerd currently uses a local-only Core Data `NSPersistentContainer`. The approved future direction is iCloud synchronization and multi-user Herd sharing using Core Data and CloudKit, as specified in [Info/CLOUDKIT_COLLABORATION.md](Info/CLOUDKIT_COLLABORATION.md). Do not describe that target as already implemented. A SwiftData migration, compatibility layer, or dual-write path is not required.

- Do not reintroduce SwiftData production repositories, models, migration adapters, or supporting infrastructure.
- Do not treat historical SwiftData implementation or historical planning documents as the active architecture.
- Preserve data integrity, object identity, relationship behavior, history, and Core Data recovery paths when they are affected by a change.

## Approved CloudKit feature work

The explicitly requested [CloudKit synchronization and collaboration specification](Info/CLOUDKIT_COLLABORATION.md) defines intended feature behavior, implementation stages, acceptance criteria, and CloudKit-specific review requirements. This is the only approved new feature document; it is not a progress tracker or evidence that features have shipped.

ChatGPT owns implementation and PR fixes. Codex is used only for code review, not implementation, documentation authoring, test creation, or CI work.

For any CloudKit, sharing, Herd selection, Core Data model migration, or related persistence work:

- Read the specification and the current affected production source before making changes. The latest production code remains authoritative for existing implementation details; user-approved feature requirements determine intended behavior.
- Implement only the stage requested by the user and its demonstrably necessary dependencies. Do not automatically execute later stages or reintroduce discarded infrastructure.
- Preserve existing data, application UUIDs, transaction semantics, repository boundaries, offline use, and recovery behavior.
- Trace both private and shared store ownership, every relevant read/write path, remote-change invalidation, navigation, permissions, deletion, invitation lifecycle, and account changes.
- If a technical approach in the specification conflicts with current code or verified platform behavior, investigate and select the smallest correct solution. Obtain approval before altering a product requirement; update the approved specification when warranted.
- ChatGPT inspects the final production diff, performs available builds and the applicable manual cases defined in Section 5 of the specification, and reports pass/fail/not-executed with environment limitations. Codex reviews the actual PR for production defects; ChatGPT fixes confirmed findings. Compilation or an absence of review comments does not establish cross-account synchronization.

This user-requested specification is an exception to the restriction on creating additional Markdown documents. Related automated tests and CI changes follow the test-driven implementation requirements above; unrelated documentation and tracking frameworks remain out of scope.

## CloudKit feature integration branch and final review

For the ongoing CloudKit synchronization and Herd-sharing feature, `feature/cloudkit-collaboration` is the integration branch. It starts from the current `main` baseline but is **not** the production release branch. This rule applies only to CloudKit feature work; unrelated changes retain their normal branching process.

- Start each new CloudKit stage/workstream branch from the latest `feature/cloudkit-collaboration` and open its PR **into that feature branch**, not `main`. Existing open CloudKit stage PRs must also be retargeted to this branch.
- Each stage PR remains narrowly scoped, includes its affected production code and focused tests together, and must pass GitHub Actions test execution and substantive Codex review before merging into the integration branch. Do not bypass failing checks to accumulate incomplete work. Fix concrete defects in the stage PR; do not adjust unrelated CI or tests to obtain green checks.
- Review stage changes against the current integration branch, including all previously merged CloudKit stages and relevant local application paths. Track dependencies via PR base/merges; do not create extra progress trackers or separate process artifacts.
- Maintain one **draft feature-integration PR from `feature/cloudkit-collaboration` into `main`** so the complete cumulative diff is visible. Keep it draft throughout implementation; do not merge or mark ready until the entire requested feature is complete and all release gates in the CloudKit specification are satisfied.
- Before the final merge, review the **full cumulative feature diff**, re-run the full test suite against the latest integration head, resolve Codex and human review findings, and perform the specification's real-device, multi-account and CloudKit production-environment verification. Earlier green stage PRs are not evidence that the integrated feature works.
- Incorporate intervening `main` changes carefully when necessary without rewriting or discarding reviewed stage changes. Preserve the stable release branch and existing local data throughout feature development.

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
- A successful build is not proof that reported runtime behavior was fixed.
- Do not claim to have executed builds or verified behavior when that was not done.
- Before submitting a PR, inspect the final diff for unrelated changes, duplicate logic, unnecessary complexity, and accidentally restored files.
- Report what changed, the root cause where applicable, the production paths inspected, verification actually performed, and remaining limitations.
