#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODEL="yaHerd/Data/CoreData/yaHerdModel.xcdatamodeld/yaHerdModel.xcdatamodel/contents"
EXPECTED_MODEL_BLOB="39c09ff3c09bc8da482826d74e3ec9c38a4dc1c0"

[[ -f "$MODEL" ]] || { echo "Core Data model is missing: $MODEL" >&2; exit 1; }

actual_model_blob="$(git hash-object "$MODEL")"
if [[ "$actual_model_blob" != "$EXPECTED_MODEL_BLOB" ]]; then
  echo "Core Data model no longer matches the Milestone 2 schema contract." >&2
  echo "Expected model blob: $EXPECTED_MODEL_BLOB" >&2
  echo "Actual model blob:   $actual_model_blob" >&2
  echo "Update the model and this verification contract together when a schema change is intentional." >&2
  exit 1
fi

python3 - "$MODEL" <<'PYTHON'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

path = Path(sys.argv[1])
root = ET.parse(path).getroot()
failures = []

expected_entities = {
    "Herd": "CDHerd",
    "TagColorDefinition": "CDTagColorDefinition",
    "AnimalStatusReference": "CDAnimalStatusReference",
    "PastureGroup": "CDPastureGroup",
    "Pasture": "CDPasture",
    "Animal": "CDAnimal",
    "AnimalTag": "CDAnimalTag",
    "MovementRecord": "CDMovementRecord",
    "StatusRecord": "CDStatusRecord",
    "HealthRecord": "CDHealthRecord",
    "PregnancyCheck": "CDPregnancyCheck",
    "FieldCheckSession": "CDFieldCheckSession",
    "FieldCheckAnimalCheck": "CDFieldCheckAnimalCheck",
    "FieldCheckFinding": "CDFieldCheckFinding",
    "WorkingTreatmentTemplate": "CDWorkingTreatmentTemplate",
    "WorkingSession": "CDWorkingSession",
    "WorkingQueueItem": "CDWorkingQueueItem",
    "WorkingTreatmentRecord": "CDWorkingTreatmentRecord",
}

entities = {entity.get("name"): entity for entity in root.findall("entity")}
if set(entities) != set(expected_entities):
    missing = sorted(set(expected_entities) - set(entities))
    extra = sorted(set(entities) - set(expected_entities))
    if missing:
        failures.append(f"missing entities: {', '.join(missing)}")
    if extra:
        failures.append(f"unexpected entities: {', '.join(extra)}")

for name, represented_class in expected_entities.items():
    entity = entities.get(name)
    if entity is None:
        continue

    if entity.get("representedClassName") != represented_class:
        failures.append(
            f"{name}: representedClassName must be {represented_class}"
        )

    if entity.get("syncable") != "NO":
        failures.append(f"{name}: syncable must be NO")

    if entity.find("uniquenessConstraints") is not None:
        failures.append(f"{name}: Core Data uniqueness constraints are prohibited")

    attributes = {item.get("name"): item for item in entity.findall("attribute")}
    identifier = attributes.get("id")
    if identifier is None:
        failures.append(f"{name}: missing id attribute")
    elif identifier.get("attributeType") != "UUID" or identifier.get("optional") != "NO":
        failures.append(f"{name}: id must be a required UUID")

    id_indexes = [
        index for index in entity.findall("fetchIndex")
        if index.get("name") == "by_id"
    ]
    if not id_indexes or not any(
        element.get("property") == "id"
        for index in id_indexes
        for element in index.findall("fetchIndexElement")
    ):
        failures.append(f"{name}: missing by_id fetch index")

    source = Path("yaHerd/Data/CoreData/ManagedObjects") / f"{represented_class}.swift"
    if not source.is_file():
        failures.append(f"{name}: missing managed-object source {source}")

    if name == "Herd":
        continue

    herd = next(
        (item for item in entity.findall("relationship") if item.get("name") == "herd"),
        None,
    )
    if herd is None:
        failures.append(f"{name}: missing Herd scope")
    elif (
        herd.get("destinationEntity") != "Herd"
        or herd.get("optional") != "NO"
        or herd.get("maxCount") != "1"
        or herd.get("deletionRule") != "Nullify"
        or herd.get("inverseEntity") != "Herd"
    ):
        failures.append(f"{name}: invalid Herd ownership relationship")

    herd_entity = entities.get("Herd")
    if herd_entity is not None:
        inverse_name = herd.get("inverseName") if herd is not None else None
        inverse = next(
            (
                item
                for item in herd_entity.findall("relationship")
                if item.get("name") == inverse_name
            ),
            None,
        )
        if (
            inverse is None
            or inverse.get("destinationEntity") != name
            or inverse.get("inverseName") != "herd"
            or inverse.get("deletionRule") != "Cascade"
            or inverse.get("toMany") != "YES"
        ):
            failures.append(f"{name}: invalid inverse Herd ownership relationship")

if failures:
    print("Core Data verification failed:", file=sys.stderr)
    for failure in failures:
        print(failure, file=sys.stderr)
    raise SystemExit(1)

print("Core Data schema contract passed.")
PYTHON

if grep -R --line-number --include='*.swift' 'import SwiftData' \
  yaHerd/Data/CoreData \
  yaHerd/Data/Persistence/CoreData \
  yaHerd/Data/Repositories/CoreData; then
  echo 'Core Data implementation must not import SwiftData.' >&2
  exit 1
fi

echo 'Core Data verification passed.'
