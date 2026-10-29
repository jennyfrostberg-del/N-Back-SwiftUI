//
//  GameViewModel.swift
//  N-Back-SwiftUI
//
//  Game state, state machine, timer and match handling. No navigation, no views.
//

import Foundation

/// Counters for one stimulus type (visual or audio) during a round.
struct ModalityResult {
    var hits = 0
    var falseAlarms = 0
    var misses = 0
}

/// Holds all game state and the rules of a round (MVVM: ViewModel).
@MainActor
final class GameViewModel: ObservableObject {

    // MARK: Published state (the view subscribes to these)

    /// H-02: every change is saved, so the settings survive an app restart.
    @Published var settings: GameSettings {
        didSet { settingsStore.save(settings) }
    }
    @Published private(set) var phase = GamePhase.idle
    /// How many events have been shown so far (HUD, S-06).
    @Published private(set) var shownEventCount = 0
    /// The highlighted grid cell, or nil when no cell is highlighted.
    @Published private(set) var highlightedCellIndex: Int?
    @Published private(set) var visualResult = ModalityResult()
    @Published private(set) var audioResult = ModalityResult()
    @Published private(set) var lastScore = 0
    @Published private(set) var highScore: Int
    /// True once the score of the finished round has been saved to the history (H-03).
    @Published private(set) var isLastScoreSaved = false
    @Published private(set) var hasSaveFailed = false

    // MARK: Private state

    private var isSavingScore = false
    private var visualSequence: [Int] = []
    private var audioSequence: [Int] = []
    private var hasRespondedVisually = false
    private var hasRespondedAudibly = false
    private var roundTask: Task<Void, Never>?
    private var generator: SeededGenerator

    private let speechService: SpeechSpeaking
    private let highScoreStore: HighScoreStoring
    private let settingsStore: SettingsStoring
    private let scoreRepository: ScoreRepositoring

    /// - Parameter seed: fixed seed for tests. Nil gives a different sequence every round.
    init(
        speechService: SpeechSpeaking = SpeechService(),
        highScoreStore: HighScoreStoring = UserDefaultsHighScoreStore(),
        settingsStore: SettingsStoring = UserDefaultsSettingsStore(),
        scoreRepository: ScoreRepositoring = ScoreRepository(),
        seed: UInt64? = nil
    ) {
        self.speechService = speechService
        self.highScoreStore = highScoreStore
        self.settingsStore = settingsStore
        self.scoreRepository = scoreRepository
        self.settings = settingsStore.load()
        self.generator = SeededGenerator(seed: seed ?? UInt64.random(in: 0...UInt64.max))
        self.highScore = highScoreStore.highScore
    }

    // MARK: Derived values

    /// H-05: true if audio is used but the device has no voice, so the view can show a message.
    /// The round still runs visually.
    var isVoiceMissing: Bool {
        settings.stimulusMode.isAudioActive && !speechService.isVoiceAvailable
    }

    /// P-04: "correct answers" in the HUD is the total number of hits.
    var totalHits: Int { visualResult.hits + audioResult.hits }

    /// The latest false alarm count, so the view can animate when it changes (P-05).
    var totalFalseAlarms: Int { visualResult.falseAlarms + audioResult.falseAlarms }

    // MARK: State machine transitions

    /// idle/finished -> running. Called from a button tap, so speech starts after a user action (G-07).
    func startRound() {
        roundTask?.cancel()
        speechService.stop()

        visualSequence = NBackSequenceGenerator.generateSequence(
            length: settings.eventsPerRound,
            n: settings.n,
            valueCount: settings.cellCount,
            using: &generator
        )
        // SEQ-06: the audio sequence is generated separately from the visual one.
        audioSequence = NBackSequenceGenerator.generateSequence(
            length: settings.eventsPerRound,
            n: settings.n,
            valueCount: settings.letterCount,
            using: &generator
        )

        shownEventCount = 0
        highlightedCellIndex = nil
        visualResult = ModalityResult()
        audioResult = ModalityResult()
        isLastScoreSaved = false
        hasSaveFailed = false
        phase = .running

        roundTask = Task { [weak self] in
            await self?.runRound()
        }
    }

    /// running -> idle. Called when the player leaves the screen (G-06).
    func stopRound() {
        roundTask?.cancel()
        roundTask = nil
        speechService.stop()
        highlightedCellIndex = nil
        if phase == .running {
            phase = .idle
        }
    }

    /// running -> finished. Counts the score and saves the high score.
    private func finishRound() {
        roundTask?.cancel()
        roundTask = nil
        speechService.stop()
        highlightedCellIndex = nil

        lastScore = ScoreCalculator.score(
            hits: totalHits,
            falseAlarms: totalFalseAlarms,
            misses: visualResult.misses + audioResult.misses
        )
        if lastScore > highScore {
            highScore = lastScore
            highScoreStore.save(highScore: lastScore)
        }
        phase = .finished
    }

    // MARK: Score history

    /// Saves the score of the finished round under a name (H-03). Saves only once per round.
    /// - Parameter playerName: the name typed by the player. An empty name becomes "Player".
    func saveLastScore(playerName: String) async {
        guard phase == .finished, !isLastScoreSaved, !isSavingScore else { return }
        isSavingScore = true
        defer { isSavingScore = false }

        let trimmedName = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty ? "Player" : trimmedName

        do {
            try await scoreRepository.save(name: name, score: lastScore, date: Date())
            isLastScoreSaved = true
            hasSaveFailed = false
        } catch {
            hasSaveFailed = true
        }
    }

    // MARK: Timer and event tick

    /// The round timer: one tick, then wait one event duration, until the round is over.
    /// Each event is shown for the whole duration except a short blank pause at the end,
    /// so the player can see when the stimulus changes, also to the same cell.
    private func runRound() async {
        let blankPause = GameSettings.blankPauseDuration

        while phase == .running {
            advanceToNextEvent()
            guard phase == .running else { return }
            do {
                try await Task.sleep(for: .seconds(settings.eventDuration - blankPause))
                highlightedCellIndex = nil
                try await Task.sleep(for: .seconds(blankPause))
            } catch {
                return // cancelled by stopRound() or finishRound()
            }
        }
    }

    /// One event tick (STYLE.md section 3). Internal so tests can drive ticks without real time.
    func advanceToNextEvent() {
        guard phase == .running else { return }

        // 1. Evaluate the previous event: a match without a press is a miss (P-01).
        let previousIndex = shownEventCount - 1
        if previousIndex >= 0 {
            countMissesForEvent(at: previousIndex)
        }

        // 2-3. If all events have been shown, the round is over.
        if shownEventCount == settings.eventsPerRound {
            finishRound()
            return
        }

        // 4. Show the visual stimulus.
        let newIndex = shownEventCount
        if settings.stimulusMode.isVisualActive {
            highlightedCellIndex = visualSequence[newIndex]
        }

        // 5. Speak the letter.
        if settings.stimulusMode.isAudioActive {
            speechService.speak(GameSettings.phoneticLetters[audioSequence[newIndex]])
        }

        // 6. Reset the "has responded" flags.
        hasRespondedVisually = false
        hasRespondedAudibly = false

        // 7. Update the HUD.
        shownEventCount += 1
    }

    private func countMissesForEvent(at index: Int) {
        let n = settings.n
        if settings.stimulusMode.isVisualActive,
           NBackSequenceGenerator.isMatch(in: visualSequence, at: index, n: n),
           !hasRespondedVisually {
            visualResult.misses += 1
        }
        if settings.stimulusMode.isAudioActive,
           NBackSequenceGenerator.isMatch(in: audioSequence, at: index, n: n),
           !hasRespondedAudibly {
            audioResult.misses += 1
        }
    }

    // MARK: Match presses

    /// The player pressed the visual match button.
    func registerVisualMatchPress() {
        guard settings.stimulusMode.isVisualActive, isMatchPressAllowed, !hasRespondedVisually else { return }
        hasRespondedVisually = true // G-05: later presses on this event are ignored

        if NBackSequenceGenerator.isMatch(in: visualSequence, at: shownEventCount - 1, n: settings.n) {
            visualResult.hits += 1
        } else {
            visualResult.falseAlarms += 1
        }
    }

    /// The player pressed the audio match button.
    func registerAudioMatchPress() {
        guard settings.stimulusMode.isAudioActive, isMatchPressAllowed, !hasRespondedAudibly else { return }
        hasRespondedAudibly = true // G-05

        if NBackSequenceGenerator.isMatch(in: audioSequence, at: shownEventCount - 1, n: settings.n) {
            audioResult.hits += 1
        } else {
            audioResult.falseAlarms += 1
        }
    }

    /// G-04: a press only counts while running and after the first n events.
    /// shownEventCount - 1 is the index of the current event, so it must be >= n.
    private var isMatchPressAllowed: Bool {
        phase == .running && shownEventCount - 1 >= settings.n
    }
}
