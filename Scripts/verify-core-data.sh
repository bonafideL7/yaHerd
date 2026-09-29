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
import re
import sys
import xml.etree.ElementTree as ET

model_path = Path(sys.argv[1])
managed_object_root = Path(sys.argv[2])
failures = []

# Maintained compatibility contract for schema already consumed by production code.
# New entities/attributes/relationships/indexes are allowed. Existing contracted
# semantics may change only when this contract is intentionally updated with them.
CLASSES = {
    "Herd": "CDHerd", "TagColorDefinition": "CDTagColorDefinition",
    "AnimalStatusReference": "CDAnimalStatusReference", "PastureGroup": "CDPastureGroup",
    "Pasture": "CDPasture", "Animal": "CDAnimal", "AnimalTag": "CDAnimalTag",
    "MovementRecord": "CDMovementRecord", "StatusRecord": "CDStatusRecord",
    "HealthRecord": "CDHealthRecord", "PregnancyCheck": "CDPregnancyCheck",
    "FieldCheckSession": "CDFieldCheckSession", "FieldCheckAnimalCheck": "CDFieldCheckAnimalCheck",
    "FieldCheckFinding": "CDFieldCheckFinding",
    "WorkingTreatmentTemplate": "CDWorkingTreatmentTemplate",
    "WorkingSession": "CDWorkingSession", "WorkingQueueItem": "CDWorkingQueueItem",
    "WorkingTreatmentRecord": "CDWorkingTreatmentRecord",
}

# name:type:required. Only absence or incompatible mutation fails; additive fields pass.
ATTRIBUTE_CONTRACT = {
    "Herd": "id:UUID:R,name:String:R,createdAt:Date:R,updatedAt:Date:R",
    "TagColorDefinition": "id:UUID:R,name:String:R,prefix:String:R,red:Double:R,green:Double:R,blue:Double:R,alpha:Double:R,sortOrder:Integer 64:R,isHidden:Boolean:R,isDefault:Boolean:R,createdAt:Date:R,updatedAt:Date:R",
    "AnimalStatusReference": "id:UUID:R,name:String:R,baseStatusRawValue:String:R",
    "PastureGroup": "id:UUID:R,name:String:R,grazeDays:Integer 64:R,restDays:Integer 64:R",
    "Pasture": "id:UUID:R,name:String:R,sortOrder:Integer 64:R,acreage:Double:O,usableAcreage:Double:O,targetAcresPerHead:Double:O,lastGrazedDate:Date:O",
    "Animal": "id:UUID:R,editorRevision:UUID:R,name:String:R,sexRawValue:String:R,birthDate:Date:R,statusRawValue:String:R,saleDate:Date:O,salePrice:Double:O,reasonSold:String:O,deathDate:Date:O,causeOfDeath:String:O,isArchived:Boolean:R,archivedAt:Date:O,archiveReason:String:O,distinguishingFeaturesData:Binary:R",
    "AnimalTag": "id:UUID:R,number:String:R,isPrimary:Boolean:R,isActive:Boolean:R,assignedAt:Date:R,removedAt:Date:O",
    "MovementRecord": "id:UUID:R,date:Date:R,fromPastureIDSnapshot:UUID:O,fromPastureNameSnapshot:String:O,toPastureIDSnapshot:UUID:O,toPastureNameSnapshot:String:O",
    "StatusRecord": "id:UUID:R,date:Date:R,oldStatusRawValue:String:R,newStatusRawValue:String:R",
    "HealthRecord": "id:UUID:R,date:Date:R,treatment:String:R,notes:String:O",
    "PregnancyCheck": "id:UUID:R,date:Date:R,resultRawValue:String:R,technician:String:O,estimatedDaysPregnant:Integer 64:O,dueDate:Date:O",
    "FieldCheckSession": "id:UUID:R,startedAt:Date:R,completedAt:Date:O,notes:String:R,expectedHeadCountSnapshot:Integer 64:R,quickCowCount:Integer 64:R,quickHeiferCount:Integer 64:R,quickCalfCount:Integer 64:R,quickBullCount:Integer 64:R,quickSteerCount:Integer 64:R,pastureIDSnapshot:UUID:R,pastureNameSnapshot:String:R,pastureArchivedAt:Date:O",
    "FieldCheckAnimalCheck": "id:UUID:R,animalIDSnapshot:UUID:R,rosterTagNumberSnapshot:String:R,rosterTagColorIDSnapshot:UUID:O,damRosterTagNumberSnapshot:String:O,damRosterTagColorIDSnapshot:UUID:O,animalNameSnapshot:String:R,animalSexRawValueSnapshot:String:R,animalTypeRawValueSnapshot:String:R,wasExpectedAtStart:Boolean:R,countedAt:Date:O,missingConfirmedAt:Date:O",
    "FieldCheckFinding": "id:UUID:R,recordedAt:Date:R,typeRawValue:String:R,severityRawValue:String:R,statusRawValue:String:R,note:String:R,animalIDSnapshot:UUID:O,animalDisplayTagNumberSnapshot:String:O,animalDisplayTagColorIDSnapshot:UUID:O,animalNameSnapshot:String:O,pastureNameSnapshot:String:R",
    "WorkingTreatmentTemplate": "id:UUID:R,name:String:R,itemsData:Binary:R",
    "WorkingSession": "id:UUID:R,date:Date:R,statusRawValue:String:R,treatmentTemplateNameSnapshot:String:R,plannedTreatmentsData:Binary:R,sourcePastureIDSnapshot:UUID:R,sourcePastureNameSnapshot:String:R",
    "WorkingQueueItem": "id:UUID:R,statusRawValue:String:R,completedAt:Date:O,animalIDSnapshot:UUID:R,animalTagNumberSnapshot:String:R,animalTagColorIDSnapshot:UUID:O,animalNameSnapshot:String:R,animalSexRawValueSnapshot:String:R,animalDamDisplayTagNumberSnapshot:String:O,animalDamDisplayTagColorIDSnapshot:UUID:O,collectedFromPastureIDSnapshot:UUID:O,collectedFromPastureNameSnapshot:String:O,destinationPastureIDSnapshot:UUID:O,destinationPastureNameSnapshot:String:O",
    "WorkingTreatmentRecord": "id:UUID:R,date:Date:R,treatmentItemID:UUID:R,itemNameSnapshot:String:R,given:Boolean:R,doseAmount:Double:O,doseUnitRawValue:String:O,administrationRouteRawValue:String:O,animalIDSnapshot:UUID:R",
}

INDEX_CONTRACT = {
    "Herd": "by_id:id", "TagColorDefinition": "by_id:id",
    "AnimalStatusReference": "by_id:id", "PastureGroup": "by_id:id",
    "Pasture": "by_id:id,by_sortOrder:sortOrder",
    "Animal": "by_id:id,by_statusRawValue:statusRawValue,by_birthDate:birthDate,by_isArchived:isArchived",
    "AnimalTag": "by_id:id,by_number:number,by_isActive:isActive,by_isPrimary:isPrimary",
    "MovementRecord": "by_id:id", "StatusRecord": "by_id:id", "HealthRecord": "by_id:id",
    "PregnancyCheck": "by_id:id",
    "FieldCheckSession": "by_id:id,by_startedAt:startedAt,by_completedAt:completedAt",
    "FieldCheckAnimalCheck": "by_id:id",
    "FieldCheckFinding": "by_id:id,by_statusRawValue:statusRawValue,by_recordedAt:recordedAt",
    "WorkingTreatmentTemplate": "by_id:id",
    "WorkingSession": "by_id:id,by_statusRawValue:statusRawValue,by_date:date",
    "WorkingQueueItem": "by_id:id", "WorkingTreatmentRecord": "by_id:id",
}

# name:destination:required-or-optional:one-or-many:delete-rule:inverse
RELATIONSHIP_CONTRACT = {
    "TagColorDefinition": "herd:Herd:R:1:Nullify:tagColors,tags:AnimalTag:O:M:Nullify:color",
    "AnimalStatusReference": "herd:Herd:R:1:Nullify:statusReferences,animals:Animal:O:M:Nullify:statusReference",
    "PastureGroup": "herd:Herd:R:1:Nullify:pastureGroups,pastures:Pasture:O:M:Nullify:group",
    "Pasture": "herd:Herd:R:1:Nullify:pastures,group:PastureGroup:O:1:Nullify:pastures,animals:Animal:O:M:Nullify:currentPasture,workingSourceSessions:WorkingSession:O:M:Nullify:sourcePasture,workingCollectedQueueItems:WorkingQueueItem:O:M:Nullify:collectedFromPasture,workingDestinationQueueItems:WorkingQueueItem:O:M:Nullify:destinationPasture,fieldCheckSessions:FieldCheckSession:O:M:Nullify:pasture",
    "Animal": "herd:Herd:R:1:Nullify:animals,statusReference:AnimalStatusReference:O:1:Nullify:animals,currentPasture:Pasture:O:1:Nullify:animals,sire:Animal:O:1:Nullify:sireOffspring,sireOffspring:Animal:O:M:Nullify:sire,dam:Animal:O:1:Nullify:damOffspring,damOffspring:Animal:O:M:Nullify:dam,activeWorkingSession:WorkingSession:O:1:Nullify:activeAnimals,tags:AnimalTag:O:M:Cascade:animal,movementRecords:MovementRecord:O:M:Cascade:animal,statusRecords:StatusRecord:O:M:Cascade:animal,healthRecords:HealthRecord:O:M:Cascade:animal,pregnancyChecks:PregnancyCheck:O:M:Cascade:animal,pregnancyChecksAsSire:PregnancyCheck:O:M:Nullify:sire,fieldCheckAnimalChecks:FieldCheckAnimalCheck:O:M:Nullify:animal,fieldCheckFindings:FieldCheckFinding:O:M:Nullify:animal,workingQueueItems:WorkingQueueItem:O:M:Nullify:animal,workingTreatmentRecords:WorkingTreatmentRecord:O:M:Nullify:animal",
    "AnimalTag": "herd:Herd:R:1:Nullify:animalTags,color:TagColorDefinition:O:1:Nullify:tags,animal:Animal:R:1:Nullify:tags",
    "MovementRecord": "herd:Herd:R:1:Nullify:movementRecords,animal:Animal:R:1:Nullify:movementRecords",
    "StatusRecord": "herd:Herd:R:1:Nullify:statusRecords,animal:Animal:R:1:Nullify:statusRecords",
    "HealthRecord": "herd:Herd:R:1:Nullify:healthRecords,animal:Animal:R:1:Nullify:healthRecords,workingSession:WorkingSession:O:1:Nullify:healthRecords",
    "PregnancyCheck": "herd:Herd:R:1:Nullify:pregnancyChecks,animal:Animal:R:1:Nullify:pregnancyChecks,sire:Animal:O:1:Nullify:pregnancyChecksAsSire,workingSession:WorkingSession:O:1:Nullify:pregnancyChecks",
    "FieldCheckSession": "herd:Herd:R:1:Nullify:fieldCheckSessions,pasture:Pasture:O:1:Nullify:fieldCheckSessions,animalChecks:FieldCheckAnimalCheck:O:M:Cascade:session,findings:FieldCheckFinding:O:M:Cascade:session",
    "FieldCheckAnimalCheck": "herd:Herd:R:1:Nullify:fieldCheckAnimalChecks,animal:Animal:O:1:Nullify:fieldCheckAnimalChecks,session:FieldCheckSession:R:1:Nullify:animalChecks",
    "FieldCheckFinding": "herd:Herd:R:1:Nullify:fieldCheckFindings,animal:Animal:O:1:Nullify:fieldCheckFindings,session:FieldCheckSession:R:1:Nullify:findings",
    "WorkingTreatmentTemplate": "herd:Herd:R:1:Nullify:workingTreatmentTemplates",
    "WorkingSession": "herd:Herd:R:1:Nullify:workingSessions,sourcePasture:Pasture:O:1:Nullify:workingSourceSessions,activeAnimals:Animal:O:M:Nullify:activeWorkingSession,queueItems:WorkingQueueItem:O:M:Cascade:session,treatmentRecords:WorkingTreatmentRecord:O:M:Cascade:session,healthRecords:HealthRecord:O:M:Cascade:workingSession,pregnancyChecks:PregnancyCheck:O:M:Cascade:workingSession",
    "WorkingQueueItem": "herd:Herd:R:1:Nullify:workingQueueItems,collectedFromPasture:Pasture:O:1:Nullify:workingCollectedQueueItems,destinationPasture:Pasture:O:1:Nullify:workingDestinationQueueItems,animal:Animal:O:1:Nullify:workingQueueItems,session:WorkingSession:R:1:Nullify:queueItems",
    "WorkingTreatmentRecord": "herd:Herd:R:1:Nullify:workingTreatmentRecords,animal:Animal:O:1:Nullify:workingTreatmentRecords,session:WorkingSession:R:1:Nullify:treatmentRecords",
}

try:
    root = ET.parse(model_path).getroot()
except ET.ParseError as error:
    print(f"Core Data model is invalid XML: {error}", file=sys.stderr)
    raise SystemExit(1)

entity_list = root.findall("entity")
entities = {entity.get("name"): entity for entity in entity_list}
if not entity_list:
    failures.append("model contains no entities")
if None in entities or len(entities) != len(entity_list):
    failures.append("every entity must have a unique name")

def parse_attributes(spec):
    result = {}
    for item in filter(None, spec.split(",")):
        name, kind, requirement = item.split(":")
        result[name] = (kind, requirement == "O")
    return result

def parse_indexes(spec):
    result = {}
    for item in filter(None, spec.split(",")):
        name, prop = item.split(":")
        result[name] = prop
    return result

def parse_relationships(spec):
    result = {}
    for item in filter(None, spec.split(",")):
        name, destination, requirement, cardinality, delete_rule, inverse = item.split(":")
        result[name] = (destination, requirement == "O", cardinality == "M", delete_rule, inverse)
    return result

ATTRIBUTE_SWIFT_TYPES = {
    "UUID": ("UUID", "UUID?"),
    "String": ("String", "String?"),
    "Date": ("Date", "Date?"),
    "Double": ("Double", "NSNumber?"),
    "Integer 64": ("Int64", "NSNumber?"),
    "Boolean": ("Bool", "NSNumber?"),
    "Binary": ("Data", "Data?"),
}

def validate_managed_object_source(entity_name, entity, represented_class):
    source = managed_object_root / f"{represented_class}.swift"
    if not source.is_file():
        failures.append(f"{entity_name}: missing managed-object source {source}")
        return

    text = source.read_text()
    objc_pattern = rf"@objc\s*\(\s*{re.escape(represented_class)}\s*\)"
    class_pattern = rf"\b(?:final\s+)?class\s+{re.escape(represented_class)}\s*:\s*NSManagedObject\b"
    if re.search(objc_pattern, text) is None:
        failures.append(f"{entity_name}: {represented_class} must declare @objc({represented_class})")
    if re.search(class_pattern, text) is None:
        failures.append(f"{entity_name}: {represented_class} must inherit NSManagedObject")

    declarations = {
        match.group(1): re.sub(r"\s+", "", match.group(2))
        for match in re.finditer(
            r"@NSManaged\s+(?:public\s+|internal\s+|private\s+|fileprivate\s+)?var\s+"
            r"([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([^\n/{]+)",
            text,
        )
    }

    for attribute in entity.findall("attribute"):
        name = attribute.get("name")
        attribute_type = attribute.get("attributeType")
        optional = attribute.get("optional") == "YES"
        expected_types = ATTRIBUTE_SWIFT_TYPES.get(attribute_type)
        if expected_types is None:
            failures.append(
                f"{entity_name}.{name}: verifier has no Swift mapping for Core Data type {attribute_type!r}"
            )
            continue
        expected = expected_types[1 if optional else 0]
        actual = declarations.get(name)
        if actual is None:
            failures.append(f"{entity_name}.{name}: missing @NSManaged attribute declaration")
        elif actual != expected:
            failures.append(
                f"{entity_name}.{name}: @NSManaged type must be {expected}, found {actual}"
            )

    for relationship in entity.findall("relationship"):
        name = relationship.get("name")
        optional = relationship.get("optional") == "YES"
        to_many = relationship.get("toMany") == "YES"
        destination = entities.get(relationship.get("destinationEntity"))
        destination_class = destination.get("representedClassName") if destination is not None else None
        if to_many:
            expected = "NSSet?" if optional else "NSSet"
        elif destination_class:
            expected = destination_class + ("?" if optional else "")
        else:
            continue
        actual = declarations.get(name)
        if actual is None:
            failures.append(f"{entity_name}.{name}: missing @NSManaged relationship declaration")
        elif actual != expected:
            failures.append(
                f"{entity_name}.{name}: @NSManaged type must be {expected}, found {actual}"
            )

for name, represented_class in CLASSES.items():
    entity = entities.get(name)
    if entity is None:
        failures.append(f"{name}: contracted entity is missing")
        continue

    if entity.get("representedClassName") != represented_class:
        failures.append(f"{name}: representedClassName must remain {represented_class}")
    if entity.get("syncable") != "NO":
        failures.append(f"{name}: syncable must remain NO")
    if entity.find("uniquenessConstraints") is not None:
        failures.append(f"{name}: Core Data uniqueness constraints are prohibited")

    validate_managed_object_source(name, entity, represented_class)

    actual_attributes = {item.get("name"): item for item in entity.findall("attribute")}
    for attribute_name, (attribute_type, optional) in parse_attributes(ATTRIBUTE_CONTRACT[name]).items():
        attribute = actual_attributes.get(attribute_name)
        if attribute is None:
            failures.append(f"{name}.{attribute_name}: contracted attribute is missing")
        elif attribute.get("attributeType") != attribute_type or (attribute.get("optional") == "YES") != optional:
            requirement = "optional" if optional else "required"
            failures.append(f"{name}.{attribute_name}: must remain {requirement} {attribute_type}")

    actual_indexes = {
        index.get("name"): index for index in entity.findall("fetchIndex") if index.get("name")
    }
    for index_name, property_name in parse_indexes(INDEX_CONTRACT[name]).items():
        index = actual_indexes.get(index_name)
        if index is None or not any(
            element.get("property") == property_name for element in index.findall("fetchIndexElement")
        ):
            failures.append(f"{name}: contracted index {index_name} must index {property_name}")

    actual_relationships = {
        relationship.get("name"): relationship
        for relationship in entity.findall("relationship")
        if relationship.get("name")
    }
    for relationship_name, expected in parse_relationships(RELATIONSHIP_CONTRACT.get(name, "")).items():
        relationship = actual_relationships.get(relationship_name)
        if relationship is None:
            failures.append(f"{name}.{relationship_name}: contracted relationship is missing")
            continue
        destination, optional, to_many, delete_rule, inverse_name = expected
        if (
            relationship.get("destinationEntity") != destination
            or (relationship.get("optional") == "YES") != optional
            or (relationship.get("toMany") == "YES") != to_many
            or relationship.get("deletionRule") != delete_rule
            or relationship.get("inverseName") != inverse_name
            or relationship.get("inverseEntity") != destination
        ):
            failures.append(
                f"{name}.{relationship_name}: relationship contract changed "
                f"(destination/cardinality/optionality/delete rule/inverse)"
            )

# Every entity, including future additions, must satisfy the durable architecture rules.
herd_entity = entities.get("Herd")
for name, entity in entities.items():
    if name is None:
        continue
    represented_class = entity.get("representedClassName")
    if not represented_class:
        failures.append(f"{name}: representedClassName is required")
    elif name not in CLASSES:
        validate_managed_object_source(name, entity, represented_class)

    if entity.get("syncable") != "NO":
        failures.append(f"{name}: syncable must be NO")
    if entity.find("uniquenessConstraints") is not None:
        failures.append(f"{name}: Core Data uniqueness constraints are prohibited")

    attributes = {item.get("name"): item for item in entity.findall("attribute")}
    identifier = attributes.get("id")
    if identifier is None or identifier.get("attributeType") != "UUID" or identifier.get("optional") != "NO":
        failures.append(f"{name}: id must be a required UUID")

    indexes = {index.get("name"): index for index in entity.findall("fetchIndex")}
    id_index = indexes.get("by_id")
    if id_index is None or not any(
        element.get("property") == "id" for element in id_index.findall("fetchIndexElement")
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
            failures.append(f"{name}.{relationship_name}: destination {destination_name!r} does not exist")
            continue
        inverse_name = relationship.get("inverseName")
        inverse = next(
            (item for item in destination.findall("relationship") if item.get("name") == inverse_name),
            None,
        )
        if (
            not inverse_name
            or relationship.get("inverseEntity") != destination_name
            or inverse is None
            or inverse.get("destinationEntity") != name
            or inverse.get("inverseName") != relationship_name
            or inverse.get("inverseEntity") != name
        ):
            failures.append(f"{name}.{relationship_name}: relationship inverse must be reciprocal")

    if name != "Herd":
        herd = relationships.get("herd")
        if (
            herd is None
            or herd.get("destinationEntity") != "Herd"
            or herd.get("optional") != "NO"
            or herd.get("maxCount") != "1"
            or herd.get("deletionRule") != "Nullify"
        ):
            failures.append(f"{name}: must have required Nullify Herd scope")
        elif herd_entity is not None:
            inverse = next(
                (item for item in herd_entity.findall("relationship") if item.get("name") == herd.get("inverseName")),
                None,
            )
            if (
                inverse is None
                or inverse.get("destinationEntity") != name
                or inverse.get("deletionRule") != "Cascade"
                or inverse.get("toMany") != "YES"
            ):
                failures.append(f"{name}: Herd must cascade its owned inverse relationship")

if failures:
    print("Core Data verification failed:", file=sys.stderr)
    for failure in failures:
        print(f"  - {failure}", file=sys.stderr)
    raise SystemExit(1)

print(f"Core Data schema contract passed ({len(entity_list)} entities).")
PYTHON

if grep -R --line-number --include='*.swift' 'import SwiftData' \
  yaHerd/Data/CoreData \
  yaHerd/Data/Persistence/CoreData \
  yaHerd/Data/Repositories/CoreData; then
  echo 'Core Data implementation must not import SwiftData.' >&2
  exit 1
fi

echo 'Core Data verification passed.'
