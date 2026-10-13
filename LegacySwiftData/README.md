# Frozen yaHerd SwiftData schema — historical source only

This folder contains the 19 **byte-identical original SwiftData model, schema and compatibility source files** that were removed from the `yaHerd` production source root after the Core Data-only runtime switch.

- Source paths are relocated from `yaHerd/Data/...` to `LegacySwiftData/Data/...` with no edits to the Swift files.
- `Scripts/verify-architecture.sh` pins each archived source's original Git blob SHA-1 and rejects missing, modified or additional Swift source files. The same script rejects any Xcode project reference to this folder.
- Neither the `yaHerd` application nor `yaHerdTests` compiles this archive. The production equivalents of the shared pregnancy and Working status enums live in `yaHerd/Domain`.
- These definitions are retained to support review and design of a **separately approved, data-preserving historical-user upgrade**. They do not provide a runtime reader, converter, import mechanism, or a fallback SwiftData store.
- Existing-device legacy stores, SQLite journal/sidecar bytes and other user files are protected by `CoreDataLegacyStorePreflight` and non-mutating recovery/export. Moving these source files does not convert or expose historical user records in Core Data.

**Release blocker:** do not ship the Core Data cutover as a lossless upgrade to users with SwiftData records until historical data conversion/import or another explicit preservation path has been implemented, reviewed and validated. Do not delete old user stores to make the app start.
