# SampleLargeDataService normalization notes

Based on `Pasture Animals.txt`, using these rules:

- `/` and `think it's` values are imported as retired tags.
- `lost tag` entries are active animals with no current tag and the former tag stored as retired.
- `UT` animals keep an empty current tag.
- `+1` creates a calf record, with the top `2026 Calves` section taking precedence for 2026 birth dates where both sources existed.
- `nursing` creates a prior-season calf when a distinct calf record was not already explicit.
- `moved` lines are imported as `MovementRecord` timeline events.
- `PREG` creates a positive `PregnancyCheck` dated in late 2025.

Generated snapshot counts by current pasture:

| Pasture | Total records | Active | Dead | 2026 birth records |
|---|---:|---:|---:|---:|
| NW Pasture | 39 | 35 | 4 | 7 |
| SW Pasture | 69 | 68 | 1 | 19 |
| Wally's Pasture | 43 | 39 | 4 | 8 |
| LF Pasture | 61 | 57 | 4 | 19 |
| NE Pasture | 47 | 45 | 2 | 7 |
| No current pasture | 4 | 4 | 0 | 0 |

Known remaining ambiguities preserved as reasonable placeholders:

- Some count-only sections required filler untagged prior-season calves to keep the snapshot aligned with herd counts.
- LF includes explicit dead-calf note records in addition to the top-section 2026 birth list.
- SW `White Sox` was linked to dam `374` because the dates align.
- NE `402/Purple 69` was normalized as current tag `402` with retired purple tag `69`.
- Animals moved out with no destination were left with no current pasture and a movement record to `External`.