//
//  NBackModel.swift
//  N-Back-SwiftUI
//
//  Pure game logic and data. No SwiftUI in this file (STYLE.md: Model layer).
//

import Foundation

// MARK: - Basic types

/// Which stimulus types are used in a round (S-03).
enum StimulusMode: String, CaseIterable, Identifiable {
    case visual
    case audio
    case dual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visual: return "Visual"
        case .audio: return "Audio"
        case .dual: return "Both"
        }
    }

    var isVisualActive: Bool { self == .visual || self == .dual }
    var isAudioActive: Bool { self == .audio || self == .dual }
}

/// The three states of the game state machine (G-01).
enum GamePhase {
    case idle
    case running
    case finished
}

/// Settings for one round. Fixed defaults for now (S-04 only requires showing them).
struct GameSettings {
    /// How many steps back a match refers to.
    var n = 2
    /// Seconds each event is shown.
    var eventDuration = 2.0
    /// Number of events in one round.
    var eventsPerRound = 20
    /// Grid is gridSize x gridSize (ST-01).
    var gridSize = 3
    /// How many of the phonetic letters are used (the first `letterCount` in `phoneticLetters`).
    var letterCount = 8
    var stimulusMode = StimulusMode.visual

    static let defaultMatchProbability = 0.3

    /// Seconds at the end of each event when no cell is highlighted. The short blank makes
    /// a new event visible even when it is the same cell as the one before.
    static let blankPauseDuration = 0.3

    /// SPEC ST-02/ST-03: the spoken letters. Chosen because they sound clearly different
    /// from each other. Confusable letters such as B/D/P/V/E/G are left out on purpose.
    static let phoneticLetters = ["C", "H", "K", "L", "Q", "R", "S", "T"]

    /// Number of grid cells, e.g. 9 for 3x3.
    var cellCount: Int { gridSize * gridSize }
}

// MARK: - Random source

/// A random number generator that gives the same numbers for the same seed.
/// Used so the sequence generator can be tested deterministically (SEQ-05).
/// Algorithm: SplitMix64.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Sequence generation

/// Generates stimulus sequences. Our own code, no library does the sequence logic.
struct NBackSequenceGenerator {

    /// Generates one sequence of stimulus indexes (SEQ-01).
    ///
    /// - Parameters:
    ///   - length: number of events in the sequence.
    ///   - n: how many steps back a match refers to.
    ///   - valueCount: number of distinct stimuli (9 grid cells, 8 letters, ...). Must be 2 or more.
    ///   - matchProbability: chance (0...1) that an event from index n and onwards is a match.
    ///   - generator: the random source (inject a `SeededGenerator` in tests).
    /// - Returns: a list of `length` values, each in `0..<valueCount`.
    static func generateSequence(
        length: Int,
        n: Int,
        valueCount: Int,
        matchProbability: Double = GameSettings.defaultMatchProbability,
        using generator: inout some RandomNumberGenerator
    ) -> [Int] {
        var sequence: [Int] = []

        for index in 0..<length {
            // SEQ-03: the first n events have nothing n steps back, so they are never matches.
            if index < n {
                sequence.append(Int.random(in: 0..<valueCount, using: &generator))
                continue
            }

            let valueNStepsBack = sequence[index - n]

            // SEQ-02: this is where we decide if the event is a match.
            let shouldBeMatch = Double.random(in: 0..<1, using: &generator) < matchProbability

            if shouldBeMatch {
                sequence.append(valueNStepsBack)
            } else {
                // SEQ-04: actively avoid a match. Pick from the other (valueCount - 1) values:
                // draw a number in 0..<valueCount-1 and skip over the forbidden value.
                var value = Int.random(in: 0..<(valueCount - 1), using: &generator)
                if value >= valueNStepsBack {
                    value += 1
                }
                sequence.append(value)
            }
        }
        return sequence
    }

    /// True if the event at `index` has the same value as the event n steps back.
    /// Events with index < n can never be matches (SEQ-03).
    static func isMatch(in sequence: [Int], at index: Int, n: Int) -> Bool {
        guard index >= n, index < sequence.count else { return false }
        return sequence[index] == sequence[index - n]
    }
}

// MARK: - Score

/// The score formula (P-02), defined in one place.
struct ScoreCalculator {

    /// score = max(0, 2 * hits - falseAlarms - misses)
    ///
    /// Why these weights: a hit is the goal, so it counts double. A false alarm and a miss
    /// each cost one point, so neither pressing all the time nor never pressing pays off.
    /// The result is clamped to 0 so the score is never negative (P-03).
    static func score(hits: Int, falseAlarms: Int, misses: Int) -> Int {
        max(0, 2 * hits - falseAlarms - misses)
    }
}

// MARK: - Settings storage

/// Loads and saves the game settings (H-02). A protocol so tests can use a fake.
protocol SettingsStoring {
    func load() -> GameSettings
    func save(_ settings: GameSettings)
}

/// Keeps the settings in UserDefaults so they survive an app restart.
struct UserDefaultsSettingsStore: SettingsStoring {
    private enum Key {
        static let n = "settings.n"
        static let eventDuration = "settings.eventDuration"
        static let eventsPerRound = "settings.eventsPerRound"
        static let gridSize = "settings.gridSize"
        static let letterCount = "settings.letterCount"
        static let stimulusMode = "settings.stimulusMode"
    }

    /// Reads each value. A value that was never saved keeps its default from `GameSettings`.
    func load() -> GameSettings {
        let defaults = UserDefaults.standard
        var settings = GameSettings()

        if let n = defaults.object(forKey: Key.n) as? Int { settings.n = n }
        if let duration = defaults.object(forKey: Key.eventDuration) as? Double { settings.eventDuration = duration }
        if let events = defaults.object(forKey: Key.eventsPerRound) as? Int { settings.eventsPerRound = events }
        if let gridSize = defaults.object(forKey: Key.gridSize) as? Int { settings.gridSize = gridSize }
        if let letterCount = defaults.object(forKey: Key.letterCount) as? Int { settings.letterCount = letterCount }
        if let rawMode = defaults.string(forKey: Key.stimulusMode),
           let mode = StimulusMode(rawValue: rawMode) {
            settings.stimulusMode = mode
        }
        return settings
    }

    func save(_ settings: GameSettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.n, forKey: Key.n)
        defaults.set(settings.eventDuration, forKey: Key.eventDuration)
        defaults.set(settings.eventsPerRound, forKey: Key.eventsPerRound)
        defaults.set(settings.gridSize, forKey: Key.gridSize)
        defaults.set(settings.letterCount, forKey: Key.letterCount)
        defaults.set(settings.stimulusMode.rawValue, forKey: Key.stimulusMode)
    }
}

// MARK: - High score storage

/// Stores the high score (P-06). A protocol so tests can use a fake.
protocol HighScoreStoring {
    var highScore: Int { get }
    func save(highScore: Int)
}

/// Keeps the high score in UserDefaults.
struct UserDefaultsHighScoreStore: HighScoreStoring {
    private static let key = "highScore"

    var highScore: Int {
        UserDefaults.standard.integer(forKey: Self.key)
    }

    func save(highScore: Int) {
        UserDefaults.standard.set(highScore, forKey: Self.key)
    }
}
