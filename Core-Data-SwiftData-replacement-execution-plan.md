{\rtf1\ansi\ansicpg1252\cocoartf2822
\cocoatextscaling0\cocoaplatform0{\fonttbl\f0\froman\fcharset0 Times-Roman;\f1\froman\fcharset0 Times-Bold;\f2\fmodern\fcharset0 Courier;
}
{\colortbl;\red255\green255\blue255;\red0\green0\blue0;\red255\green255\blue255;}
{\*\expandedcolortbl;;\cssrgb\c0\c1\c1;\cssrgb\c100000\c100000\c99985;}
{\*\listtable{\list\listtemplateid1\listhybrid{\listlevel\levelnfc0\levelnfcn0\leveljc0\leveljcn0\levelfollow0\levelstartat1\levelspace360\levelindent0{\*\levelmarker \{decimal\}}{\leveltext\leveltemplateid1\'01\'00;}{\levelnumbers\'01;}\fi-360\li720\lin720 }{\listname ;}\listid1}}
{\*\listoverridetable{\listoverride\listid1\listoverridecount0\ls1}}
\margl1440\margr1440\vieww11520\viewh8400\viewkind0
\deftab720
\pard\pardeftab720\sa240\partightenfactor0

\f0\fs24 \cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3 For the core data refactor and gutting swift data, layout a detailed plan with milestones that you can follow and understand. you'll be doing all the work. I agree with the approach of first establishing tests before changing the data model.\'a0\
\
Yes. With that change, the safest sequence is 
\f1\b \cf2 \strokec3 characterize and lock behavior first, then replace persistence underneath it
\f0\b0 \cf2 \strokec3 . The existing SwiftData implementation becomes the behavioral reference, but the tests themselves should be written so they survive the cutover and run unchanged against Core Data.\
The existing 
\f1\b \cf2 \strokec3 Core Data model blueprint PR #75 is still valid
\f0\b0 \cf2 \strokec3  because it is documentation only; it does not modify the persistence model. I would not add the 
\f2\fs26 \cf2 \strokec3 .xcdatamodeld
\f0\fs24 \cf2 \strokec3  or Core Data runtime implementation until the test milestone below is complete.\
\pard\pardeftab720\sa298\partightenfactor0

\f1\b\fs36 \cf2 \strokec3 Core Data / SwiftData replacement execution plan\
\pard\tx220\tx720\pardeftab720\li720\fi-720\sa240\partightenfactor0
\ls1\ilvl0
\fs24 \cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	1	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3 Milestone 0 \'97 Freeze the behavioral contract with reusable tests
\f0\b0 \cf2 \strokec3 \uc0\u8232 This is now the first implementation milestone.\u8232 The goal is not to test SwiftData. The goal is to define what yaHerd persistence is required to do regardless of storage technology.\u8232 I will create a reusable persistence contract-test structure under something like:\u8232 
\f2\fs26 \cf2 \strokec3 \uc0\u8232 yaHerdTests/\
\pard\tx220\tx720\pardeftab720\li720\fi-720\partightenfactor0
\ls1\ilvl0\cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	2	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3   PersistenceContracts/\
\ls1\ilvl0\cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	3	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3     PersistenceContractHarness.swift\
\ls1\ilvl0\cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	4	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3     AnimalRepositoryContractTests.swift\
\ls1\ilvl0\cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	5	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3     AnimalAggregateTransactionContractTests.swift\
\ls1\ilvl0\cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	6	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3     PastureRepositoryContractTests.swift\
\ls1\ilvl0\cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	7	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3     PastureDeletionTransactionContractTests.swift\
\ls1\ilvl0\cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	8	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3     FieldCheckRepositoryContractTests.swift\
\ls1\ilvl0\cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	9	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3     WorkingRepositoryContractTests.swift\
\ls1\ilvl0\cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	10	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3     HerdRepositoryContractTests.swift\
\ls1\ilvl0\cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	11	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3     TagColorRepositoryContractTests.swift\
\ls1\ilvl0\cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	12	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3     HealthRepositoryContractTests.swift\
\ls1\ilvl0\cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	13	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3     IdentityContractTests.swift\
\ls1\ilvl0\cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	14	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3     MutationBoundaryContractTests.swift\
\ls1\ilvl0\cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	15	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3 \
\ls1\ilvl0\cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	16	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3   SwiftDataPersistenceContracts/\
\ls1\ilvl0\cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	17	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3     SwiftDataContractHarness.swift\uc0\u8232 \u8232 \u8232 \u8232 \u8232 \u8232 \u8232 \u8232 \u8232 \u8232 \u8232 \u8232 \u8232 \u8232 \u8232 \u8232 \u8232 
\f0\fs24 \cf2 \strokec3 The reusable tests will operate through Domain repository and transaction protocols. They should not import SwiftData, use 
\f2\fs26 \cf2 \strokec3 ModelContext
\f0\fs24 \cf2 \strokec3 , inspect SwiftData models, or depend on fetch implementation.\uc0\u8232 The SwiftData harness will exist only to instantiate the current implementation and prove the contracts describe actual intended behavior. Later we add a Core Data harness to the same tests. Once Core Data passes them and SwiftData is removed, only the small SwiftData harness disappears; the contract tests remain permanently.\u8232 The behavioral coverage needs to include at least these areas.\u8232 
\f1\b \cf2 \strokec3 Identity:
\f0\b0 \cf2 \strokec3  UUID survives create/read/update/reload; relationships resolve by application UUID; IDs never change during edits; duplicate application IDs fail rather than silently producing a second logical entity.\uc0\u8232 
\f1\b \cf2 \strokec3 Animal aggregate:
\f0\b0 \cf2 \strokec3  create tagged and untagged animals; update scalar fields; sire/dam relationships; pasture assignment; active/retired tags; exactly-one-primary-tag rules; tag retirement history; stale aggregate revision rejection; failed aggregate update leaves the original aggregate unchanged.\uc0\u8232 
\f1\b \cf2 \strokec3 Animal state/history:
\f0\b0 \cf2 \strokec3  active/sold/deceased/archive behavior; status changes create appropriate history; movement changes current pasture and records movement history; historical data remains readable after related live records disappear where that is part of product behavior.\uc0\u8232 
\f1\b \cf2 \strokec3 Pastures:
\f0\b0 \cf2 \strokec3  create/update/order/group behavior; resident queries; movement into/out of pasture; pasture deletion moves residents according to the Domain plan; field-check history retains pasture snapshots after deletion; the whole delete workflow rolls back on failure.\uc0\u8232 
\f1\b \cf2 \strokec3 Field Check:
\f0\b0 \cf2 \strokec3  create session; expected-head-count snapshot; tracked animals; counted/missing state; findings; finding-to-animal/session associations; completed session behavior; archived-pasture behavior.\uc0\u8232 
\f1\b \cf2 \strokec3 Working:
\f0\b0 \cf2 \strokec3  create session; collect animals; move animals into working-pen state; queue-item lifecycle; treatment records; pregnancy checks; observations/castration generated records; edit completed work; complete session and return animals; destination assignment validation; delete active session and restore animals; rollback when a multi-record operation fails.\uc0\u8232 
\f1\b \cf2 \strokec3 Reference/support data:
\f0\b0 \cf2 \strokec3  tag colors, animal status references, treatment templates, herd ownership/scoping, sorting and visibility behavior used by Presentation.\uc0\u8232 
\f1\b \cf2 \strokec3 Mutation semantics:
\f0\b0 \cf2 \strokec3  failed persistence operations do not publish successful mutation events; successful logical operations publish only after commit.\uc0\u8232 
\f1\b \cf2 \strokec3 Gate to leave Milestone 0:
\f0\b0 \cf2 \strokec3  the important current workflows are represented by reusable contracts, the current SwiftData implementation passes them, and we can point to a test for every high-risk behavior we intend Core Data to preserve.\uc0\u8232 This milestone replaces the earlier abandoned PR #71 approach. The difference is important: these are no longer temporary SwiftData-specific tests. They become the permanent specification for both implementations.\
\pard\tx220\tx720\pardeftab720\li720\fi-720\sa240\partightenfactor0
\ls1\ilvl0
\f1\b \cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	18	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3 Milestone 1 \'97 Finalize the Core Data model blueprint
\f0\b0 \cf2 \strokec3 \uc0\u8232 After the behavior suite exists, I will reconcile PR #75 against anything the tests reveal.\u8232 This is where we settle the final entity/relationship design before creating the actual model.\u8232 The blueprint remains based on the finished product rather than cloning SwiftData. The current decisions should remain unless tests expose a real product requirement: UUID application identity on every durable entity, 
\f2\fs26 \cf2 \strokec3 AnimalTag
\f0\fs24 \cf2 \strokec3 as the only persisted tag state, derived animal location, explicit historical snapshots, Herd as the ownership/share root, no bridge revision records, no duplicate SwiftData compatibility fields, and no migration support for development SwiftData stores.\uc0\u8232 I will also produce a clear mapping from each Domain contract to the Core Data entities it depends on. That gives us a traceable reason for every field and relationship in the model.\u8232 
\f1\b \cf2 \strokec3 Gate:
\f0\b0 \cf2 \strokec3  every persisted field and relationship has an application purpose, delete behavior is decided, history semantics are decided, and there are no fields whose justification is merely \'93SwiftData used to have this.\'94\
\ls1\ilvl0
\f1\b \cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	19	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3 Milestone 2 \'97 Add the production Core Data model, but do not cut the app over
\f0\b0 \cf2 \strokec3 \uc0\u8232 Create the real 
\f2\fs26 \cf2 \strokec3 yaHerdModel.xcdatamodeld
\f0\fs24 \cf2 \strokec3  from the approved blueprint.\uc0\u8232 This PR establishes the physical schema only. SwiftData remains the running implementation.\u8232 I will define the managed-object classes, application UUID attributes, inverse relationships, delete rules, indexes, optionality, Core Data configurations, and CloudKit-compatible model characteristics.\u8232 This milestone also introduces 
\f1\b \cf2 \strokec3 schema tests
\f0\b0 \cf2 \strokec3  that inspect 
\f2\fs26 \cf2 \strokec3 NSManagedObjectModel
\f0\fs24 \cf2 \strokec3  directly. These are separate from repository contracts. They verify things such as required UUIDs, expected entities, relationship inverses, delete rules, configuration membership, forbidden unique constraints if they conflict with CloudKit requirements, and absence of accidental SwiftData compatibility entities.\uc0\u8232 No repository behavior changes yet.\u8232 
\f1\b \cf2 \strokec3 Gate:
\f0\b0 \cf2 \strokec3  the Core Data model can be loaded independently and its structural tests pass.\
\ls1\ilvl0
\f1\b \cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	20	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3 Milestone 3 \'97 Build the final Core Data persistence foundation
\f0\b0 \cf2 \strokec3 \uc0\u8232 Introduce the infrastructure that will survive production:\u8232 
\f2\fs26 \cf2 \strokec3 \uc0\u8232 Data/Persistence/CoreData/\
\pard\tx220\tx720\pardeftab720\li720\fi-720\partightenfactor0
\ls1\ilvl0\cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	21	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3   CoreDataPersistenceAssembly\
\ls1\ilvl0\cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	22	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3   CoreDataPersistentContainer\
\ls1\ilvl0\cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	23	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3   CoreDataStoreRouter\
\ls1\ilvl0\cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	24	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3   CoreDataTransactionExecutor\
\ls1\ilvl0\cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	25	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3   CoreDataContextFactory\
\ls1\ilvl0\cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	26	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3   CoreDataLookup\
\ls1\ilvl0\cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	27	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3   CoreDataPersistenceError\uc0\u8232 \u8232 \u8232 \u8232 \u8232 \u8232 \u8232 \u8232 \u8232 \u8232 \u8232 \u8232 \u8232 \u8232 \u8232 \u8232 \u8232 
\f0\fs24 \cf2 \strokec3 Local-only mode uses a normal Core Data store.\uc0\u8232 iCloud mode uses one 
\f2\fs26 \cf2 \strokec3 NSPersistentCloudKitContainer
\f0\fs24 \cf2 \strokec3  with the intended private/shared topology. Persistent history and remote-change support are configured here, not in Presentation.\uc0\u8232 Context policy is established here as well: view/read contexts, private write contexts where appropriate, merge policy, transaction boundaries, rollback behavior, and store assignment rules.\u8232 No SwiftData/Core Data bridge is created.\u8232 
\f1\b \cf2 \strokec3 Gate:
\f0\b0 \cf2 \strokec3  we can create local/private/shared test stores, insert managed objects, save/reload them, and prove UUID/store-routing behavior independently of the app.\
\pard\tx220\tx720\pardeftab720\li720\fi-720\sa240\partightenfactor0
\ls1\ilvl0
\f1\b \cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	28	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3 Milestone 4 \'97 Implement low-dependency Core Data repositories
\f0\b0 \cf2 \strokec3 \uc0\u8232 Start with the graph roots and simpler repositories because everything else depends on them.\u8232 This should cover Herd, pasture groups, pastures, tag colors, animal status references, and treatment templates.\u8232 For each repository, the exact same contract suite created in Milestone 0 will get a Core Data runner.\u8232 SwiftData and Core Data will temporarily coexist in source, but the app still uses SwiftData. This is not dual-writing; each implementation is isolated and Core Data is exercised only by tests.\u8232 
\f1\b \cf2 \strokec3 Gate:
\f0\b0 \cf2 \strokec3  Core Data passes the relevant permanent contract tests without weakening the tests to accommodate it.\
\ls1\ilvl0
\f1\b \cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	29	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3 Milestone 5 \'97 Implement the Animal aggregate and transaction boundary
\f0\b0 \cf2 \strokec3 \uc0\u8232 This is the first major persistence replacement.\u8232 Implement Animal, AnimalTag, parent relationships, status records, movements, health records, pregnancy checks, archive state, and editor aggregate revision handling.\u8232 
\f2\fs26 \cf2 \strokec3 AnimalAggregateTransactionWriting
\f0\fs24 \cf2 \strokec3  becomes a real Core Data transaction rather than several repository saves.\uc0\u8232 Create and update must execute within one transaction context. Tag reconciliation, history generation, pasture/parent relationships, stale-revision checking, and aggregate revision rotation happen before the final save.\u8232 Any failure rolls back the entire logical edit.\u8232 This milestone also replaces the current duplicated tag-number/color state with the production 
\f2\fs26 \cf2 \strokec3 AnimalTag
\f0\fs24 \cf2 \strokec3  model.\uc0\u8232 
\f1\b \cf2 \strokec3 Gate:
\f0\b0 \cf2 \strokec3  all reusable animal/identity/history/transaction contracts pass against Core Data, including deliberately injected failures and stale-edit conflicts.\
\ls1\ilvl0
\f1\b \cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	30	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3 Milestone 6 \'97 Implement Pasture deletion and movement transactions
\f0\b0 \cf2 \strokec3 \uc0\u8232 Replace the current sequential pasture-deletion behavior with the transaction boundary already defined in Domain.\u8232 The transaction will revalidate the expected pasture/resident state, move affected animals, create movement history, preserve Field Check snapshots/history, and delete the pasture records in one atomic operation.\u8232 Animal movement itself should also have a clean reusable Core Data implementation because Working and pasture workflows both depend on it.\u8232 
\f1\b \cf2 \strokec3 Gate:
\f0\b0 \cf2 \strokec3  no test can observe the half-completed state that is possible with the current multi-save SwiftData sequence.\
\ls1\ilvl0
\f1\b \cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	31	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3 Milestone 7 \'97 Implement Field Check persistence
\f0\b0 \cf2 \strokec3 \uc0\u8232 Port Field Check sessions, tracked-animal checks, findings, quick counts, snapshots, completion/archive behavior, and their repository operations.\u8232 Historical semantics matter more here than live relationships. The Core Data model must preserve the snapshots the UI expects even when an animal or pasture later changes or disappears.\u8232 Multi-record commands remain transactionally atomic.\u8232 
\f1\b \cf2 \strokec3 Gate:
\f0\b0 \cf2 \strokec3  the entire Field Check contract suite passes against Core Data, including pasture deletion/history cases.\
\ls1\ilvl0
\f1\b \cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	32	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3 Milestone 8 \'97 Implement Working persistence
\f0\b0 \cf2 \strokec3 \uc0\u8232 Port working sessions, queue items, treatment records, pregnancy checks linked to working sessions, generated health records, and treatment templates.\u8232 This milestone preserves the useful behavior already present in the SwiftData implementation while dropping deprecated storage concepts such as queue indices/order and old persistence terminology.\u8232 The important existing atomic operations remain atomic: collect animals, complete queue item, save queue-item edits, complete session, and delete session.\u8232 
\f1\b \cf2 \strokec3 Gate:
\f0\b0 \cf2 \strokec3  all Working contract tests pass against Core Data, including animal-location restoration, treatment replacement, destination assignment validation, and rollback cases.\
\ls1\ilvl0
\f1\b \cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	33	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3 Milestone 9 \'97 Port read models and performance-sensitive queries
\f0\b0 \cf2 \strokec3 \uc0\u8232 Once the authoritative write-side repositories exist, implement the Dashboard, Home, animal lists, search/filtering, metrics, and other read-heavy paths directly against Core Data.\u8232 This is where we avoid recreating the current \'93fetch everything and filter on the main actor\'94 behavior.\u8232 Queries should perform filtering, sorting, counts, grouping, and projections in Core Data where practical.\u8232 Persistence work should not automatically remain 
\f2\fs26 \cf2 \strokec3 @MainActor
\f0\fs24 \cf2 \strokec3  merely because SwiftData previously required it.\uc0\u8232 
\f1\b \cf2 \strokec3 Gate:
\f0\b0 \cf2 \strokec3  feature snapshots match the test-defined behavior while the new implementation has sane query boundaries for real herd sizes.\
\ls1\ilvl0
\f1\b \cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	34	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3 Milestone 10 \'97 Direct Core Data + CloudKit synchronization and sharing
\f0\b0 \cf2 \strokec3 \uc0\u8232 Only after the local graph is stable do we implement final synchronization.\u8232 Same-user sync comes from the same 
\f2\fs26 \cf2 \strokec3 NSPersistentCloudKitContainer
\f0\fs24 \cf2 \strokec3 .\uc0\u8232 Cross-user Herd sharing uses Core Data/CloudKit sharing APIs directly against that graph. There is no 
\f2\fs26 \cf2 \strokec3 Shared*Record
\f0\fs24 \cf2 \strokec3 mirror graph, SwiftData exporter, SwiftData importer, reconciliation journal, or second synchronization lifecycle.\uc0\u8232 Remote Core Data/CloudKit changes feed the existing persistence-neutral application mutation/invalidation mechanism.\u8232 Tests here focus on deterministic boundaries we control: store routing, ownership/root assumptions, share-preparation logic, share acceptance routing, remote-change invalidation, and application UUID preservation.\u8232 
\f1\b \cf2 \strokec3 Gate:
\f0\b0 \cf2 \strokec3  there is exactly one production data graph and one synchronization system.\
\ls1\ilvl0
\f1\b \cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	35	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3 Milestone 11 \'97 Cut AppDependencies over to Core Data
\f0\b0 \cf2 \strokec3 \uc0\u8232 This is the decisive runtime switch.\u8232 
\f2\fs26 \cf2 \strokec3 CoreDataPersistenceAssembly
\f0\fs24 \cf2 \strokec3  becomes the application persistence assembly. All feature dependency containers receive Core Data-backed implementations of the existing Domain contracts.\uc0\u8232 SwiftUI does not receive 
\f2\fs26 \cf2 \strokec3 NSManagedObjectContext
\f0\fs24 \cf2 \strokec3 , 
\f2\fs26 \cf2 \strokec3 NSPersistentContainer
\f0\fs24 \cf2 \strokec3 , or managed objects.\uc0\u8232 The app either runs entirely on Core Data or fails visibly during development. There is no fallback to SwiftData and no screen-by-screen hybrid runtime.\u8232 
\f1\b \cf2 \strokec3 Gate:
\f0\b0 \cf2 \strokec3  all production dependency paths resolve to Core Data, the app has no runtime reads or writes to SwiftData, and the behavioral contract suite passes against the implementation actually used by the app.\
\ls1\ilvl0
\f1\b \cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	36	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3 Milestone 12 \'97 Gut SwiftData and the old sharing bridge
\f0\b0 \cf2 \strokec3 \uc0\u8232 Once the cutover is proven, delete rather than adapt.\u8232 This removes the SwiftData models, SwiftData repositories, SwiftData read actors, SwiftData persistence assembly, 
\f2\fs26 \cf2 \strokec3 ModelContainer
\f0\fs24 \cf2 \strokec3 /
\f2\fs26 \cf2 \strokec3 ModelContext
\f0\fs24 \cf2 \strokec3  startup, SwiftData schema/migration infrastructure, SwiftData remote-store observer, SwiftData-specific repair machinery, SwiftData/Core Data bridge, 
\f2\fs26 \cf2 \strokec3 Shared*Record
\f0\fs24 \cf2 \strokec3  mirrors, bridge snapshots/import/export, bridge journals, reconciliation code, deferred bridge repositories, bridge diagnostics that no longer apply, and the temporary SwiftData contract-test harness.\uc0\u8232 Domain tests and reusable persistence contracts remain.\u8232 
\f1\b \cf2 \strokec3 Gate:
\f0\b0 \cf2 \strokec3  a production-code search finds no SwiftData runtime dependency and no old mirror/bridge architecture.\
\ls1\ilvl0
\f1\b \cf2 \kerning1\expnd0\expndtw0 \outl0\strokewidth0 {\listtext	37	}\cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec3 Milestone 13 \'97 Harden the final architecture
\f0\b0 \cf2 \strokec3 \uc0\u8232 Add architecture checks that prevent regression.\u8232 Production Domain and Presentation must not import Core Data. Only the Data/App persistence implementation can know managed-object/context/store types.\u8232 Architecture verification should explicitly reject SwiftData imports and old bridge classes.\u8232 Add final Core Data integration tests for delete rules, transaction rollback, store routing, UUID integrity, persistent-history handling, and mapping.\u8232 Update 
\f2\fs26 \cf2 \strokec3 ARCHITECTURE.md
\f0\fs24 \cf2 \strokec3  to describe the implemented system rather than the transition. Delete 
\f2\fs26 \cf2 \strokec3 CORE_DATA_CUTOVER.md
\f0\fs24 \cf2 \strokec3  because the transition is complete.\uc0\u8232 
\f1\b \cf2 \strokec3 Final completion gate:
\f0\b0 \cf2 \strokec3  Core Data is the sole persistence system; the permanent behavior suite passes against it; CloudKit private/shared storage uses the same graph; SwiftData and the bridge are gone; UUIDs are authoritative application identity; the important multi-record workflows are genuinely transactional; and the architecture checks make it difficult to accidentally reintroduce persistence coupling.\
\pard\pardeftab720\sa280\partightenfactor0

\f1\b\fs28 \cf2 \strokec3 How I will use this plan\
\pard\pardeftab720\sa240\partightenfactor0

\f0\b0\fs24 \cf2 \strokec3 I will treat each milestone as a merge gate. I will not start the next persistence layer simply because code exists; the contracts for the current milestone need to be satisfied first. PRs will stay small enough to review, so some milestones\'97especially Animal, Working, and CloudKit sharing\'97may require multiple PRs, but I will not create transitional architectures just to make the PR sequence easier.\
The key ordering is now:\
\pard\pardeftab720\partightenfactor0

\f2\fs26 \cf2 \strokec3 \
Permanent behavioral contracts\
        \uc0\u8595 \
Core Data schema\
        \uc0\u8595 \
Core Data infrastructure\
        \uc0\u8595 \
Repositories + real transactions\
        \uc0\u8595 \
Read models\
        \uc0\u8595 \
CloudKit sync/sharing\
        \uc0\u8595 \
One-time app cutover\
        \uc0\u8595 \
Delete SwiftData + bridge\
        \uc0\u8595 \
Architecture enforcement\
\
\pard\pardeftab720\sa240\partightenfactor0

\f0\fs24 \cf2 \strokec3 The 
\f1\b \cf2 \strokec3 next implementation PR should therefore be the persistence contract-test foundation
\f0\b0 \cf2 \strokec3 , not the Core Data model itself. That gives us a measurable definition of \'93the refactor did not break yaHerd\'94 before we start changing storage.\
}