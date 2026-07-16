# SwiftData schema migrations

## Released schemas

| App release | SwiftData schema | Version | Fixture | Migration stage |
| --- | --- | --- | --- | --- |
| 1.0 | `YaHerdSchemaV1` | 1.0.0 | `YaHerdSchemaV1FixtureStore` | None; initial schema |

`YaHerdMigrationPlan.schemas` is the authoritative ordered list of released schemas. `ModelContainerFactory` must remain the only production entry point for opening the SwiftData store so every store uses that migration plan.

## Required workflow for persistent-model changes

1. Do not edit the schema version already shipped to users without introducing a new version.
2. Add the next `VersionedSchema` and append it to `YaHerdMigrationPlan.schemas`.
3. Add exactly one migration stage between the previous and new schemas.
4. Add a disk-backed fixture store for the new released schema. Keep all older fixtures.
5. Register the fixture in `YaHerdMigrationFixtureStores`; the generic migration test will open it through the current production migration plan and validate representative records.
6. Test direct upgrades from every released fixture to the current schema before merging or shipping.
7. For CloudKit-backed model changes, validate the development CloudKit schema and deploy it before releasing the app update.

The fixture coverage and stage-count tests are release gates. A schema may not be added to the migration plan without a matching fixture, migration stage, and data-validation test.

## Lightweight migration candidates

A lightweight stage may be used only when SwiftData can preserve existing rows without application-specific decisions. Typical candidates are:

- adding a new optional property;
- adding a property with a safe persistent default;
- adding a new model type that does not require backfilling existing records;
- renaming a property or model while preserving its original persistent name;
- removing a property only after confirming no migration logic or retained data is required.

Even lightweight changes require a new schema version, a migration stage, a fixture, and an upgrade test.

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

Custom migrations must validate both the transformed values and relationship graph in fixture upgrade tests. Destructive fallback or silent record deletion is not acceptable for a production migration.

## Startup data migrations

`DefaultHerdBootstrapper` and `FieldCheckHistoricalSnapshotMigrator` run after the persistent store has opened. They are data bootstrap/repair utilities, not schema migration stages. They cannot make an incompatible store open and must not be used as substitutes for `VersionedSchema`, `SchemaMigrationPlan`, or migration fixture tests.

## Fixture requirements

Each released schema fixture must:

- create an on-disk store using that exact versioned schema;
- contain deterministic representative data and relationships;
- open through `ModelContainerFactory` with the current migration plan;
- verify identifiers, scalar values, optional values, and relationships after upgrade;
- add records that exercise every field or relationship changed by that schema release.

Do not regenerate old fixture definitions from newer model types. Future schema versions should retain the old version's model definitions so old fixture stores remain an accurate representation of what shipped.
