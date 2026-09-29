#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODEL="yaHerd/Data/CoreData/yaHerdModel.xcdatamodeld/yaHerdModel.xcdatamodel/contents"
MANAGED_OBJECT_ROOT="yaHerd/Data/CoreData/ManagedObjects"

[[ -f "$MODEL" ]] || { echo "Core Data model is missing: $MODEL" >&2; exit 1; }
[[ -d "$MANAGED_OBJECT_ROOT" ]] || { echo "Managed-object source directory is missing: $MANAGED_OBJECT_ROOT" >&2; exit 1; }

python3 - "$MODEL" "$MANAGED_OBJECT_ROOT" <<'PYTHON'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

model_path = Path(sys.argv[1])
managed_object_root = Path(sys.argv[2])
failures = []

try:
    root = ET.parse(model_path).getroot()
except ET.ParseError as error:
    print(f"Core Data model is invalid XML: {error}", file=sys.stderr)
    raise SystemExit(1)

entity_list = root.findall("entity")
entities = {entity.get("name"): entity for entity in entity_list}

if not entity_list:
    failures.append("model contains no entities")
if None in entities:
    failures.append("every entity must have a name")
if len(entities) != len(entity_list):
    failures.append("entity names must be unique")

herd_entity = entities.get("Herd")
if herd_entity is None:
    failures.append("Herd ownership root is missing")

for name, entity in sorted(
    ((name, entity) for name, entity in entities.items() if name is not None),
    key=lambda item: item[0],
):
    represented_class = entity.get("representedClassName")
    if not represented_class:
        failures.append(f"{name}: representedClassName is required")
    else:
        source = managed_object_root / f"{represented_class}.swift"
        if not source.is_file():
            failures.append(f"{name}: missing managed-object source {source}")

    if entity.get("syncable") != "NO":
        failures.append(f"{name}: syncable must remain NO")

    if entity.find("uniquenessConstraints") is not None:
        failures.append(
            f"{name}: Core Data uniqueness constraints are prohibited; "
            "Herd-scoped identity belongs to repository/transaction validation"
        )

    attributes = {item.get("name"): item for item in entity.findall("attribute")}
    identifier = attributes.get("id")
    if identifier is None:
        failures.append(f"{name}: missing application id attribute")
    elif identifier.get("attributeType") != "UUID" or identifier.get("optional") != "NO":
        failures.append(f"{name}: id must be a required UUID")

    indexes = {
        index.get("name"): index
        for index in entity.findall("fetchIndex")
        if index.get("name")
    }
    id_index = indexes.get("by_id")
    if id_index is None or not any(
        element.get("property") == "id"
        for element in id_index.findall("fetchIndexElement")
    ):
        failures.append(f"{name}: missing by_id fetch index")

    relationships = {
        relationship.get("name"): relationship
        for relationship in entity.findall("relationship")
        if relationship.get("name")
    }

    for relationship_name, relationship in relationships.items():
        destination_name = relationship.get("destinationEntity")
        destination = entities.get(destination_name)
        if destination is None:
            failures.append(
                f"{name}.{relationship_name}: destination entity "
                f"{destination_name!r} does not exist"
            )
            continue

        inverse_name = relationship.get("inverseName")
        inverse_entity_name = relationship.get("inverseEntity")
        if not inverse_name or not inverse_entity_name:
            failures.append(f"{name}.{relationship_name}: inverse is required")
            continue

        if inverse_entity_name != destination_name:
            failures.append(
                f"{name}.{relationship_name}: inverseEntity must match destinationEntity"
            )
            continue

        inverse = next(
            (
                item
                for item in destination.findall("relationship")
                if item.get("name") == inverse_name
            ),
            None,
        )
        if inverse is None:
            failures.append(
                f"{name}.{relationship_name}: inverse relationship "
                f"{destination_name}.{inverse_name} does not exist"
            )
        elif (
            inverse.get("destinationEntity") != name
            or inverse.get("inverseName") != relationship_name
            or inverse.get("inverseEntity") != name
        ):
            failures.append(
                f"{name}.{relationship_name}: inverse relationship is not reciprocal"
            )

    if name == "Herd":
        continue

    herd = relationships.get("herd")
    if herd is None:
        failures.append(f"{name}: missing required Herd scope")
        continue

    if (
        herd.get("destinationEntity") != "Herd"
        or herd.get("optional") != "NO"
        or herd.get("maxCount") != "1"
        or herd.get("deletionRule") != "Nullify"
        or herd.get("inverseEntity") != "Herd"
    ):
        failures.append(f"{name}: invalid Herd ownership relationship")
        continue

    if herd_entity is not None:
        inverse_name = herd.get("inverseName")
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
            or inverse.get("inverseEntity") != name
            or inverse.get("deletionRule") != "Cascade"
            or inverse.get("toMany") != "YES"
        ):
            failures.append(f"{name}: Herd must cascade its owned inverse relationship")

if failures:
    print("Core Data verification failed:", file=sys.stderr)
    for failure in failures:
        print(f"  - {failure}", file=sys.stderr)
    raise SystemExit(1)

print(f"Core Data model verification passed ({len(entity_list)} entities).")
PYTHON

if grep -R --line-number --include='*.swift' 'import SwiftData' \
  yaHerd/Data/CoreData \
  yaHerd/Data/Persistence/CoreData \
  yaHerd/Data/Repositories/CoreData; then
  echo 'Core Data implementation must not import SwiftData.' >&2
  exit 1
fi

echo 'Core Data verification passed.'
