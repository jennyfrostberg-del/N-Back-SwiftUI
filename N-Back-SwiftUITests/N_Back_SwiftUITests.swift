//
//  N_Back_SwiftUITests.swift
//  N-Back-SwiftUITests
//
//  Unit tests for the logic layer (T-01, T-03). No UI is started.
//

import XCTest
@testable import N_Back_SwiftUI

// MARK: - Fakes

/// Records spoken letters instead of using the real speech synthesizer.
final class FakeSpeechService: SpeechSpeaking {
    var isVoiceAvailable = true
    private(set) var spokenLetters: [String] = []
    private(set) var stopCount = 0

    func speak(_ letter: String) { spokenLetters.append(letter) }
    func stop() { stopCount += 1 }
}

/// Keeps the high score in memory instead of UserDefaults.
final class FakeHighScoreStore: HighScoreStoring {
    var highScore = 0
    func save(highScore: Int) { self.highScore = highScore }
}

/// Keeps the settings in memory instead of UserDefaults.
final class FakeSettingsStore: SettingsStoring {
    var storedSettings = GameSettings()
    func load() -> GameSettings { storedSettings }
    func save(_ settings: GameSettings) { storedSettings = settings }
}

/// Keeps saved scores in memory. Can be told to fail.
final class FakeScoreRepository: ScoreRepositoring {
    struct SavedScore: Equatable {
        let name: String
        let score: Int
    }

    private(set) var savedScores: [SavedScore] = []
    var shouldFail = false

    func save(name: String, score: Int, date: Date) async throws {
        if shouldFail { throw NSError(domain: "test", code: 1) }
        savedScores.append(SavedScore(name: name, score: score))
    }

    func fetchRecords(sortedBy option: ScoreSortOption) async throws -> [ScoreRecord] { [] }
}

// MARK: - Sequence generator

final class NBackSequenceGeneratorTests: XCTestCase {

    func testSequenceHasRequestedLength() {
        var generator = SeededGenerator(seed: 1)
        let sequence = NBackSequenceGenerator.generateSequence(length: 25, n: 2, valueCount: 9, using: &generator)
        XCTAssertEqual(sequence.count, 25)
    }

    /// SEQ-03: run with many seeds, since a single lucky seed proves nothing.
    func testFirstNEventsAreNeverMatches() {
        let n = 3
        for seed in 0..<200 {
            var generator = SeededGenerator(seed: UInt64(seed))
            let sequence = NBackSequenceGenerator.generateSequence(length: 30, n: n, valueCount: 9, using: &generator)
            for index in 0..<n {
                XCTAssertFalse(NBackSequenceGenerator.isMatch(in: sequence, at: index, n: n),
                               "Event \(index) must not be a match (seed \(seed))")
            }
        }
    }

    /// SPEC: match rate should be 20-40 %. The probability is 30 %, so over many events it should be close.
    func testMatchRateIsWithin20To40Percent() {
        let n = 2
        var matches = 0
        var possibleMatches = 0
        for seed in 0..<100 {
            var generator = SeededGenerator(seed: UInt64(seed))
            let sequence = NBackSequenceGenerator.generateSequence(length: 50, n: n, valueCount: 9, using: &generator)
            for index in n..<sequence.count {
                possibleMatches += 1
                if NBackSequenceGenerator.isMatch(in: sequence, at: index, n: n) { matches += 1 }
            }
        }
        let rate = Double(matches) / Double(possibleMatches)
        XCTAssertGreaterThanOrEqual(rate, 0.2)
        XCTAssertLessThanOrEqual(rate, 0.4)
    }

    /// SEQ-04: with match probability 0, no event may match, even by accident.
    func testNonMatchEventsDoNotAccidentallyMatch() {
        for seed in 0..<100 {
            var generator = SeededGenerator(seed: UInt64(seed))
            let sequence = NBackSequenceGenerator.generateSequence(
                length: 40, n: 2, valueCount: 3, matchProbability: 0, using: &generator)
            for index in 0..<sequence.count {
                XCTAssertFalse(NBackSequenceGenerator.isMatch(in: sequence, at: index, n: 2))
            }
        }
    }

    func testSameSeedGivesSameSequence() {
        var first = SeededGenerator(seed: 42)
        var second = SeededGenerator(seed: 42)
        XCTAssertEqual(
            NBackSequenceGenerator.generateSequence(length: 20, n: 2, valueCount: 9, using: &first),
            NBackSequenceGenerator.generateSequence(length: 20, n: 2, valueCount: 9, using: &second))
    }
}

// MARK: - Score

final class ScoreCalculatorTests: XCTestCase {

    func testScoreFormulaCountsHitsAndFalseAlarmsCorrectly() {
        // 2 * 5 - 1 - 2 = 7
        XCTAssertEqual(ScoreCalculator.score(hits: 5, falseAlarms: 1, misses: 2), 7)
    }

    func testScoreIsNeverNegative() {
        XCTAssertEqual(ScoreCalculator.score(hits: 0, falseAlarms: 10, misses: 10), 0)
    }
}

// MARK: - GameViewModel

@MainActor
final class GameViewModelTests: XCTestCase {

    private var speech: FakeSpeechService!
    private var store: FakeHighScoreStore!
    private var settingsStore: FakeSettingsStore!
    private var scoreRepository: FakeScoreRepository!
    private var viewModel: GameViewModel!

    override func setUp() {
        speech = FakeSpeechService()
        store = FakeHighScoreStore()
        settingsStore = FakeSettingsStore()
        scoreRepository = FakeScoreRepository()
        viewModel = GameViewModel(speechService: speech, highScoreStore: store,
                                  settingsStore: settingsStore, scoreRepository: scoreRepository, seed: 7)
        viewModel.settings.n = 2
        viewModel.settings.eventsPerRound = 10
        viewModel.settings.stimulusMode = .visual
    }

    override func tearDown() {
        viewModel.stopRound() // cancels the real timer task started by startRound()
    }

    private func tick(_ times: Int) {
        for _ in 0..<times { viewModel.advanceToNextEvent() }
    }

    func testMatchPressBeforeStartIsIgnored() {
        viewModel.registerVisualMatchPress()
        XCTAssertEqual(viewModel.visualResult.hits + viewModel.visualResult.falseAlarms, 0)
    }

    func testMatchPressAfterFinishIsIgnored() {
        viewModel.startRound()
        tick(viewModel.settings.eventsPerRound + 1) // last tick finishes the round
        XCTAssertEqual(viewModel.phase, .finished)

        let before = viewModel.visualResult
        viewModel.registerVisualMatchPress()
        XCTAssertEqual(viewModel.visualResult.hits, before.hits)
        XCTAssertEqual(viewModel.visualResult.falseAlarms, before.falseAlarms)
    }

    func testMatchPressDuringFirstNEventsIsIgnored() {
        viewModel.startRound()
        tick(viewModel.settings.n) // events 0 and 1 are shown, both inside the first n
        viewModel.registerVisualMatchPress()
        XCTAssertEqual(viewModel.visualResult.hits + viewModel.visualResult.falseAlarms, 0)
    }

    /// T-04: this test fails if the double-press guard is removed.
    func testMatchPressTwiceOnSameEventCountsOnlyOnce() {
        viewModel.startRound()
        tick(viewModel.settings.n + 1) // first event where a press is allowed
        viewModel.registerVisualMatchPress()
        viewModel.registerVisualMatchPress()
        XCTAssertEqual(viewModel.visualResult.hits + viewModel.visualResult.falseAlarms, 1)
    }

    func testRoundFinishesAndSavesHighScore() {
        viewModel.startRound()
        tick(viewModel.settings.eventsPerRound + 1)
        XCTAssertEqual(viewModel.phase, .finished)
        XCTAssertEqual(store.highScore, viewModel.lastScore)
    }

    func testStopRoundReturnsToIdleAndStopsSpeech() {
        viewModel.startRound()
        tick(3)
        viewModel.stopRound()
        XCTAssertEqual(viewModel.phase, .idle)
        XCTAssertGreaterThan(speech.stopCount, 0)
    }

    /// H-02: a changed setting is written to the store and read back by a new ViewModel.
    func testChangedSettingsAreSavedAndLoadedAgain() {
        viewModel.settings.n = 4
        viewModel.settings.gridSize = 5

        let restartedViewModel = GameViewModel(speechService: speech, highScoreStore: store,
                                               settingsStore: settingsStore,
                                               scoreRepository: scoreRepository, seed: 7)
        XCTAssertEqual(restartedViewModel.settings.n, 4)
        XCTAssertEqual(restartedViewModel.settings.gridSize, 5)
    }

    /// H-05: the fallback message is needed only when audio is used and no voice exists.
    func testVoiceIsMissingOnlyWhenAudioIsUsedWithoutVoice() {
        speech.isVoiceAvailable = false

        viewModel.settings.stimulusMode = .audio
        XCTAssertTrue(viewModel.isVoiceMissing)

        viewModel.settings.stimulusMode = .visual
        XCTAssertFalse(viewModel.isVoiceMissing)
    }

    func testRoundStillRunsVisuallyWithoutVoice() {
        speech.isVoiceAvailable = false
        viewModel.settings.stimulusMode = .dual
        viewModel.startRound()
        tick(3)
        XCTAssertEqual(viewModel.phase, .running)
        XCTAssertNotNil(viewModel.highlightedCellIndex)
    }

    /// H-03: the score of a finished round is saved under the typed name, once.
    func testFinishedRoundScoreIsSavedOnlyOnce() async {
        viewModel.startRound()
        tick(viewModel.settings.eventsPerRound + 1)

        await viewModel.saveLastScore(playerName: "  Anna ")
        await viewModel.saveLastScore(playerName: "Anna")

        XCTAssertEqual(scoreRepository.savedScores,
                       [FakeScoreRepository.SavedScore(name: "Anna", score: viewModel.lastScore)])
        XCTAssertTrue(viewModel.isLastScoreSaved)
    }

    func testScoreCannotBeSavedBeforeRoundIsFinished() async {
        viewModel.startRound()
        tick(3)
        await viewModel.saveLastScore(playerName: "Anna")
        XCTAssertTrue(scoreRepository.savedScores.isEmpty)
    }

    func testEmptyNameIsSavedAsPlayer() async {
        viewModel.startRound()
        tick(viewModel.settings.eventsPerRound + 1)
        await viewModel.saveLastScore(playerName: "   ")
        XCTAssertEqual(scoreRepository.savedScores.first?.name, "Player")
    }

    func testFailedSaveIsReportedAndCanBeRetried() async {
        viewModel.startRound()
        tick(viewModel.settings.eventsPerRound + 1)

        scoreRepository.shouldFail = true
        await viewModel.saveLastScore(playerName: "Anna")
        XCTAssertTrue(viewModel.hasSaveFailed)
        XCTAssertFalse(viewModel.isLastScoreSaved)

        scoreRepository.shouldFail = false
        await viewModel.saveLastScore(playerName: "Anna")
        XCTAssertTrue(viewModel.isLastScoreSaved)
    }

    func testAudioModeSpeaksOneLetterPerEvent() {
        viewModel.settings.stimulusMode = .audio
        viewModel.startRound()
        tick(4)
        XCTAssertEqual(speech.spokenLetters.count, 4)
        for letter in speech.spokenLetters {
            XCTAssertTrue(GameSettings.phoneticLetters.contains(letter))
        }
    }
}

// MARK: - Score repository (real Core Data, in memory)

final class ScoreRepositoryTests: XCTestCase {

    private var repository: ScoreRepository!

    override func setUp() async throws {
        repository = ScoreRepository(persistence: PersistenceController(inMemory: true))

        // Names, scores and dates are all in different orders, so each sort gives a different list.
        try await repository.save(name: "carl", score: 10, date: Date(timeIntervalSince1970: 3_000))
        try await repository.save(name: "Anna", score: 30, date: Date(timeIntervalSince1970: 1_000))
        try await repository.save(name: "Bo", score: 20, date: Date(timeIntervalSince1970: 2_000))
    }

    func testRecordsCanBeSortedByNameIgnoringCase() async throws {
        let records = try await repository.fetchRecords(sortedBy: .name)
        XCTAssertEqual(records.map(\.name), ["Anna", "Bo", "carl"])
    }

    func testRecordsCanBeSortedByScoreHighestFirst() async throws {
        let records = try await repository.fetchRecords(sortedBy: .score)
        XCTAssertEqual(records.map(\.score), [30, 20, 10])
    }

    func testRecordsCanBeSortedByDateNewestFirst() async throws {
        let records = try await repository.fetchRecords(sortedBy: .date)
        XCTAssertEqual(records.map(\.name), ["carl", "Bo", "Anna"])
    }
}
