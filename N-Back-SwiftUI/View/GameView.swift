//
//  GameView.swift
//  N-Back-SwiftUI
//
//  Game screen: HUD, square grid, start button and match button(s) (S-05, S-06, S-07).
//  Only draws state and forwards button taps. The rules live in GameViewModel.
//

import SwiftUI

struct GameView: View {
    @EnvironmentObject private var viewModel: GameViewModel
    /// Local UI state: the text in the name field.
    @State private var playerName = ""

    var body: some View {
        // H-04: portrait puts the controls under the grid, landscape puts them beside it.
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

            Group {
                if isLandscape {
                    HStack(spacing: 24) {
                        stimulusArea
                        controls
                            .frame(maxWidth: 320)
                    }
                } else {
                    VStack(spacing: 16) {
                        stimulusArea
                        controls
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Game")
        .navigationBarTitleDisplayMode(.inline)
        // G-06: stop timer and speech when the player leaves the screen.
        .onDisappear {
            viewModel.stopRound()
        }
    }

    // MARK: Parts

    /// The grid, or a speaker icon when only audio is used.
    private var stimulusArea: some View {
        Group {
            if viewModel.settings.stimulusMode.isVisualActive {
                GridView(
                    gridSize: viewModel.settings.gridSize,
                    highlightedCellIndex: viewModel.highlightedCellIndex
                )
            } else {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        VStack(spacing: 16) {
            hud

            if viewModel.isVoiceMissing {
                VoiceMissingMessage()
            }

            if viewModel.phase == .finished {
                finishedSection
            }

            matchButtons

            Button(viewModel.phase == .running ? "Restart round" : "Start new round") {
                viewModel.startRound()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    /// Result after a round: the score, the count per stimulus type, and saving to the history (H-03).
    private var finishedSection: some View {
        VStack(spacing: 8) {
            Text("Round finished! Score: \(viewModel.lastScore)")
                .font(.headline)

            // H-01: each stimulus type is counted separately.
            if viewModel.settings.stimulusMode.isVisualActive {
                ResultSummary(title: "Position", result: viewModel.visualResult)
            }
            if viewModel.settings.stimulusMode.isAudioActive {
                ResultSummary(title: "Sound", result: viewModel.audioResult)
            }

            if viewModel.isLastScoreSaved {
                Text("Score saved")
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    TextField("Your name", text: $playerName)
                        .textFieldStyle(.roundedBorder)
                        .frame(minHeight: MatchButton.minimumTouchTarget)
                    Button("Save score") {
                        Task { await viewModel.saveLastScore(playerName: playerName) }
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: MatchButton.minimumTouchTarget)
                }
                if viewModel.hasSaveFailed {
                    Text("The score could not be saved. Try again.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// S-06: live state. "Correct answers" is the number of hits (P-04).
    private var hud: some View {
        HStack {
            Text("Event \(viewModel.shownEventCount) / \(viewModel.settings.eventsPerRound)")
            Spacer()
            Text("Correct: \(viewModel.totalHits)")
        }
        .font(.headline)
    }

    private var matchButtons: some View {
        HStack(spacing: 16) {
            if viewModel.settings.stimulusMode.isVisualActive {
                MatchButton(
                    title: viewModel.settings.stimulusMode == .dual ? "Position match" : "Match",
                    falseAlarmCount: viewModel.visualResult.falseAlarms
                ) {
                    viewModel.registerVisualMatchPress()
                }
            }
            if viewModel.settings.stimulusMode.isAudioActive {
                MatchButton(
                    title: viewModel.settings.stimulusMode == .dual ? "Sound match" : "Match",
                    falseAlarmCount: viewModel.audioResult.falseAlarms
                ) {
                    viewModel.registerAudioMatchPress()
                }
            }
        }
    }
}

// MARK: - ResultSummary

/// One line with the counts for one stimulus type.
struct ResultSummary: View {
    let title: String
    let result: ModalityResult

    var body: some View {
        Text("\(title): \(result.hits) hits, \(result.falseAlarms) false alarms, \(result.misses) misses")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

// MARK: - GridView

/// A square grid where at most one cell is highlighted (ST-01).
struct GridView: View {
    let gridSize: Int
    let highlightedCellIndex: Int?

    private let spacing: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            // H-04: the side is the smaller of the width and height, so the grid is
            // square in every orientation and on every device.
            let side = min(geometry.size.width, geometry.size.height)
            let cellSize = (side - spacing * CGFloat(gridSize - 1)) / CGFloat(gridSize)

            VStack(spacing: spacing) {
                ForEach(0..<gridSize, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<gridSize, id: \.self) { column in
                            let cellIndex = row * gridSize + column
                            RoundedRectangle(cornerRadius: 8)
                                .fill(cellIndex == highlightedCellIndex ? Color.blue : Color.gray.opacity(0.25))
                                .frame(width: cellSize, height: cellSize)
                                .accessibilityLabel("Cell \(cellIndex + 1)")
                                .accessibilityValue(cellIndex == highlightedCellIndex ? "highlighted" : "")
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            // Center the square inside the available space.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - MatchButton

/// The match button. After a wrong press it softly fades to orange and back (P-05):
/// no text and no sound, so the feedback is not judgmental.
struct MatchButton: View {
    /// H-05: Apple's minimum touch target is 44 x 44 pt.
    static let minimumTouchTarget: CGFloat = 44

    let title: String
    /// The view watches this value. When it grows, the player pressed wrongly.
    let falseAlarmCount: Int
    let action: () -> Void

    @State private var isShowingFeedback = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.title3.bold())
                .frame(maxWidth: .infinity, minHeight: 60)
        }
        .buttonStyle(.borderedProminent)
        .tint(isShowingFeedback ? .orange : .green)
        .scaleEffect(isShowingFeedback ? 0.94 : 1)
        .frame(minWidth: Self.minimumTouchTarget, minHeight: Self.minimumTouchTarget)
        .accessibilityLabel(title)
        .onChange(of: falseAlarmCount) { _ in
            showFeedback()
        }
    }

    private func showFeedback() {
        withAnimation(.easeOut(duration: 0.15)) {
            isShowingFeedback = true
        }
        withAnimation(.easeIn(duration: 0.4).delay(0.2)) {
            isShowingFeedback = false
        }
    }
}

#Preview {
    NavigationStack {
        GameView()
    }
    .environmentObject(GameViewModel())
}
