//
//  SettingsView.swift
//  N-Back-SwiftUI
//
//  Settings screen (H-02). Every change goes through GameViewModel.settings,
//  which saves it, so the values are still there after an app restart.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var viewModel: GameViewModel

    var body: some View {
        Form {
            Section("Game") {
                // The ranges keep n well below the number of events, so a round always has matches to find.
                Stepper(value: $viewModel.settings.n, in: 1...5) {
                    Text("n: \(viewModel.settings.n)")
                }
                Stepper(value: $viewModel.settings.eventsPerRound, in: 10...50, step: 5) {
                    Text("Events per round: \(viewModel.settings.eventsPerRound)")
                }
                Stepper(value: $viewModel.settings.eventDuration, in: 1...5, step: 0.5) {
                    Text("Event duration: \(viewModel.settings.eventDuration, specifier: "%.1f") s")
                }
            }

            Section("Stimuli") {
                Stepper(value: $viewModel.settings.gridSize, in: 3...5) {
                    Text("Grid: \(viewModel.settings.gridSize) x \(viewModel.settings.gridSize)")
                }
                Stepper(value: $viewModel.settings.letterCount, in: 4...GameSettings.phoneticLetters.count) {
                    Text("Distinct letters: \(viewModel.settings.letterCount)")
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environmentObject(GameViewModel())
}
