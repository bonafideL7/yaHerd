# SwiftData schema migrations

## Current pre-release schema

| Release status | SwiftData schema | Version | Fixture | Migration stage |
| --- | --- | --- | --- | --- |
| Unreleased | `YaHerdSchemaV1` | 1.0.0 | `YaHerdSchemaV1FixtureStore` | None; initial schema |

`YaHerdMigrationPlan.schemas` is the authoritative ordered schema list. `ModelContainerFactory` must remain the only production entry point for opening the SwiftData store so every store uses that plan.

`YaHerdSchemaV1` has not shipped. Until the first production release, persistent-model changes must update V1 directly and coordinate all four persistence surfaces in the same change:

1. the SwiftData V1 model;
2. the Core Data/CloudKit sharing bridge;
3. the V1 disk fixture and production-container validation;
4. repository and Working Session tests that exercise the changed data.

No migration stage or additional schema version should be created for an unreleased V1 change.

## Required workflow after V1 is released

1. Do not edit a schema version already shipped to users.
2. Add the next `VersionedSchema` and append it to `YaHerdMigrationPlan.schemas`.
3. Add exactly one migration stage between the previous and new schemas.
4. Add a disk-backed fixture store for the new released schema. Keep all older fixtures.
5. Register the fixture in `YaHerdMigrationFixtureStores`; the generic migration test must open it through the current production migration plan and validate representative records.
6. Test direct upgrades from every released fixture to the current schema before merging or shipping.
7. For CloudKit-backed model changes, validate the development CloudKit schema and deploy it before releasing the app update.

The fixture coverage and stage-count tests are release gates. After V1 ships, a schema may not be added to the migration plan without a matching fixture, migration stage, and data-validation test.

## Lightweight migration candidates

A lightweight stage may be used only when SwiftData can preserve existing rows without application-specific decisions. Typical candidates are:

- adding a new optional property;
- adding a property with a safe persistent default;
- adding a new model type that does not require backfilling existing records;
- renaming a property or model while preserving its original persistent name;
- removing a property only after confirming no migration logic or retained data is required.

After the first release, even lightweight changes require a new schema version, a migration stage, a fixture, and an upgrade test.

## Changes that require custom migration

Use `MigrationStage.custom` when any existing value must be interpreted, transformed, synthesized, reconciled, or validated. This includes:

- changing a property's stored type or encoded representation;
- making an optional property required when existing records need a backfill;
- changing enum raw values or transformable/Codable payload formats;
- splitting or combining models or properties;
- moving data between models;
- changing relationship cardinality, ownership, inverse relationships, or delete behavior when existing links need repair;
- introducing uniqueness rules that require duplicate detection or merging;
- replacing identifiers or changing identifier semantics;
- deriving new persisted values from multiple existing fields;
- preserving data while removing a property or model;
- enforcing a new business invariant on existing records.

Custom migrations must validate both transformed values and the relationship graph in fixture upgrade tests. Destructive fallback or silent record deletion is not acceptable for a production migration.

## Startup data migrations

`DefaultHerdBootstrapper` and `FieldCheckHistoricalSnapshotMigrator` run after the persistent store has opened. They are data bootstrap/repair utilities, not schema migration stages. They cannot make an incompatible store open and must not be used as substitutes for `VersionedSchema`, `SchemaMigrationPlan`, or migration fixture tests.

## Fixture requirements

Each schema fixture must:

- create an on-disk store using that exact versioned schema;
- contain deterministic representative data and relationships;
- open through `ModelContainerFactory` with the current migration plan;
- verify identifiers, scalar values, optional values, encoded values, and relationships after opening or upgrade;
- add records that exercise every field or relationship changed by that schema release.

The current V1 fixture specifically includes a Working Session, planned treatment, collected animal, and treatment record. It verifies stable treatment-item identity, dose amount/unit/route, and the deprecated queue-order fields. The sharing-bridge tests must verify the same values survive export and import while queue ordering remains ignored by active behavior.

Do not regenerate a released fixture definition from newer model types. Future schema versions must retain the old version's model definitions so old fixture stores remain an accurate representation of what shipped.
