//
//  ScoreHistoryViewModel.swift
//  N-Back-SwiftUI
//

import Foundation

/// Holds the list of saved scores and the chosen sort order for the history screen (H-03).
@MainActor
final class ScoreHistoryViewModel: ObservableObject {
    @Published private(set) var records: [ScoreRecord] = []
    @Published private(set) var sortOption = ScoreSortOption.date
    @Published private(set) var hasLoadFailed = false

    private let repository: ScoreRepositoring

    init(repository: ScoreRepositoring = ScoreRepository()) {
        self.repository = repository
    }

    /// Changes the sort order and fetches the list again, sorted by the database.
    func select(_ option: ScoreSortOption) async {
        sortOption = option
        await load()
    }

    func load() async {
        do {
            records = try await repository.fetchRecords(sortedBy: sortOption)
            hasLoadFailed = false
        } catch {
            hasLoadFailed = true
        }
    }
}
