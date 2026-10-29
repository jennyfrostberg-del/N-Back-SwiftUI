//
//  HomeView.swift
//  N-Back-SwiftUI
//
//  Home screen: high score, stimulus type choice and current settings (S-02, S-03, S-04).
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var viewModel: GameViewModel

    var body: some View {
        // ScrollView so everything is reachable on a small screen in landscape (H-04).
        ScrollView {
            VStack(spacing: 24) {
                Text("N-Back")
                    .font(.largeTitle.bold())

                Text("High score: \(viewModel.highScore)")
                    .font(.title2)

                // S-03: the player chooses visual, audio or both.
                Picker("Stimulus type", selection: $viewModel.settings.stimulusMode) {
                    ForEach(StimulusMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                // S-04: the current settings.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Stimulus type: \(viewModel.settings.stimulusMode.title)")
                    Text("n: \(viewModel.settings.n)")
                    Text("Event duration: \(viewModel.settings.eventDuration, specifier: "%.1f") s")
                    Text("Events per round: \(viewModel.settings.eventsPerRound)")
                    Text("Grid: \(viewModel.settings.gridSize) x \(viewModel.settings.gridSize)")
                    Text("Distinct letters: \(viewModel.settings.letterCount)")
                }

                if viewModel.isVoiceMissing {
                    VoiceMissingMessage()
                }

                NavigationLink("Play") {
                    GameView()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                NavigationLink("Score history") {
                    ScoreHistoryView()
                }

                NavigationLink("Settings") {
                    SettingsView()
                }
            }
            .padding()
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
    }
}

/// H-05: shown when the device has no speech voice. The round still works visually.
struct VoiceMissingMessage: View {
    var body: some View {
        Label("No speech voice was found on this device, so letters cannot be read aloud.",
              systemImage: "speaker.slash")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .environmentObject(GameViewModel())
}
