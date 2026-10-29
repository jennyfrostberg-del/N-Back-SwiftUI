//
//  ScoreRepository.swift
//  N-Back-SwiftUI
//
//  Score history stored in Core Data (H-03). No SwiftUI in this file.
//  The Core Data model is built in code, so there is no .xcdatamodeld file to keep in sync.
//

import CoreData

// MARK: - Entity

/// One saved score: name, score and date. This is the Core Data entity "ScoreEntry".
@objc(ScoreEntry)
final class ScoreEntry: NSManagedObject {
    @NSManaged var name: String
    @NSManaged var score: Int64
    @NSManaged var date: Date
}

/// A plain copy of a saved score. Safe to pass to the ViewModel and the view,
/// since a managed object must only be used on the context that created it.
struct ScoreRecord: Identifiable, Equatable {
    let id: String
    let name: String
    let score: Int
    let date: Date
}

// MARK: - Sorting

/// What the history list can be sorted on (H-03).
enum ScoreSortOption: String, CaseIterable, Identifiable {
    case name
    case score
    case date

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Name"
        case .score: return "Score"
        case .date: return "Date"
        }
    }

    /// The sort descriptor used in the fetch request, so the database does the sorting.
    /// Name sorts A to Z. Score and date sort highest and newest first.
    var sortDescriptor: NSSortDescriptor {
        switch self {
        case .name:
            // The selector makes "anna" and "Anna" sort together.
            return NSSortDescriptor(key: "name", ascending: true,
                                    selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
        case .score:
            return NSSortDescriptor(key: "score", ascending: false)
        case .date:
            return NSSortDescriptor(key: "date", ascending: false)
        }
    }
}

// MARK: - Persistence

/// Sets up the Core Data stack.
final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    /// The model is created once. Several copies would make Core Data warn that
    /// more than one entity description claims `ScoreEntry`.
    private static let model: NSManagedObjectModel = {
        let nameAttribute = NSAttributeDescription()
        nameAttribute.name = "name"
        nameAttribute.attributeType = .stringAttributeType
        nameAttribute.isOptional = false

        let scoreAttribute = NSAttributeDescription()
        scoreAttribute.name = "score"
        scoreAttribute.attributeType = .integer64AttributeType
        scoreAttribute.isOptional = false

        let dateAttribute = NSAttributeDescription()
        dateAttribute.name = "date"
        dateAttribute.attributeType = .dateAttributeType
        dateAttribute.isOptional = false

        let entity = NSEntityDescription()
        entity.name = "ScoreEntry"
        entity.managedObjectClassName = NSStringFromClass(ScoreEntry.self)
        entity.properties = [nameAttribute, scoreAttribute, dateAttribute]

        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }()

    /// - Parameter inMemory: true in tests, so nothing is written to disk.
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "NBack", managedObjectModel: Self.model)
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error {
                print("Could not load the score database: \(error)")
            }
        }
    }
}

// MARK: - Repository

/// What the ViewModels need from the score database. A protocol so tests can use a fake.
protocol ScoreRepositoring {
    func save(name: String, score: Int, date: Date) async throws
    func fetchRecords(sortedBy option: ScoreSortOption) async throws -> [ScoreRecord]
}

/// Saves and fetches scores. Both run on a background context, so the main thread is not blocked.
struct ScoreRepository: ScoreRepositoring {
    private let persistence: PersistenceController

    init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
    }

    func save(name: String, score: Int, date: Date) async throws {
        let context = persistence.container.newBackgroundContext()
        try await context.perform {
            let entry = ScoreEntry(context: context)
            entry.name = name
            entry.score = Int64(score)
            entry.date = date
            try context.save()
        }
    }

    /// - Parameter option: which attribute to sort on. The sorting is done by the fetch request.
    func fetchRecords(sortedBy option: ScoreSortOption) async throws -> [ScoreRecord] {
        let context = persistence.container.newBackgroundContext()
        return try await context.perform {
            let request = NSFetchRequest<ScoreEntry>(entityName: "ScoreEntry")
            // Newest first is the tie-breaker when two entries have the same name or score.
            request.sortDescriptors = [option.sortDescriptor,
                                       NSSortDescriptor(key: "date", ascending: false)]

            return try context.fetch(request).map { entry in
                ScoreRecord(id: entry.objectID.uriRepresentation().absoluteString,
                            name: entry.name,
                            score: Int(entry.score),
                            date: entry.date)
            }
        }
    }
}
