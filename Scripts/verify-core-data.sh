#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODEL="yaHerd/Data/CoreData/yaHerdModel.xcdatamodeld/yaHerdModel.xcdatamodel/contents"

[[ -f "$MODEL" ]] || { echo "Core Data model is missing: $MODEL" >&2; exit 1; }

python3 - "$MODEL" <<'PYTHON'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

path = Path(sys.argv[1])
root = ET.parse(path).getroot()
failures = []

entities = root.findall("entity")
if not entities:
    failures.append("Core Data model contains no entities")

for entity in entities:
    name = entity.get("name", "<unnamed>")

    if entity.get("syncable") != "NO":
        failures.append(f"{name}: syncable must be NO")

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

    if name != "Herd":
        herd = next(
            (item for item in entity.findall("relationship") if item.get("name") == "herd"),
            None,
        )
        if herd is None:
            failures.append(f"{name}: missing Herd scope")
        elif herd.get("destinationEntity") != "Herd" or herd.get("optional") != "NO":
            failures.append(f"{name}: herd must be a required Herd relationship")

    represented_class = entity.get("representedClassName")
    if represented_class:
        source = Path("yaHerd/Data/CoreData/ManagedObjects") / f"{represented_class}.swift"
        if not source.is_file():
            failures.append(f"{name}: missing managed-object source {source}")

if failures:
    print("Core Data verification failed:", file=sys.stderr)
    for failure in failures:
        print(failure, file=sys.stderr)
    raise SystemExit(1)

print("Core Data verification passed.")
PYTHON

if grep -R --line-number --include='*.swift' 'import SwiftData'   yaHerd/Data/CoreData   yaHerd/Data/Persistence/CoreData   yaHerd/Data/Repositories/CoreData; then
  echo 'Core Data implementation must not import SwiftData.' >&2
  exit 1
fi
