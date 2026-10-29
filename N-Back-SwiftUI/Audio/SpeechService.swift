//
//  SpeechService.swift
//  N-Back-SwiftUI
//

import AVFoundation

/// What the ViewModel needs from text-to-speech. A protocol so tests can use a fake.
protocol SpeechSpeaking {
    /// False if the device has no English voice (H-05).
    var isVoiceAvailable: Bool { get }
    func speak(_ letter: String)
    func stop()
}

/// Reads letters aloud with AVSpeechSynthesizer.
/// The synthesizer is created once and kept as a property. A local variable would be
/// deallocated and the speech would stop.
final class SpeechService: SpeechSpeaking {
    private let synthesizer = AVSpeechSynthesizer()

    var isVoiceAvailable: Bool {
        AVSpeechSynthesisVoice(language: "en-US") != nil
    }

    func speak(_ letter: String) {
        // .playback makes speech audible even when the silent switch is on.
        try? AVAudioSession.sharedInstance().setCategory(.playback)

        // A single uppercase letter is read as "capital C". Lowercase is read as just "C".
        let utterance = AVSpeechUtterance(string: letter.lowercased())
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
