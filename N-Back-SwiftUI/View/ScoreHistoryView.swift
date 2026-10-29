//
//  ScoreHistoryView.swift
//  N-Back-SwiftUI
//
//  Lists all saved scores, sortable on name, score and date (H-03).
//

import SwiftUI

struct ScoreHistoryView: View {
    @StateObject private var viewModel = ScoreHistoryViewModel()

    var body: some View {
        VStack {
            Picker("Sort by", selection: sortBinding) {
                ForEach(ScoreSortOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if viewModel.hasLoadFailed {
                Text("The score list could not be loaded.")
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            } else if viewModel.records.isEmpty {
                Text("No scores saved yet. Finish a round and save your score.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            } else {
                List(viewModel.records) { record in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(record.name)
                                .font(.headline)
                            Text(record.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(record.score)")
                            .font(.title2.bold())
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle("Score history")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
    }

    /// Connects the picker to the ViewModel. A new choice fetches the list again.
    private var sortBinding: Binding<ScoreSortOption> {
        Binding(
            get: { viewModel.sortOption },
            set: { newOption in
                Task { await viewModel.select(newOption) }
            }
        )
    }
}

#Preview {
    NavigationStack {
        ScoreHistoryView()
    }
}
