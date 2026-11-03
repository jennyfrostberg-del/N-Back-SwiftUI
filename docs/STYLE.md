# STYLE.md – Arkitektur och kodstil (iOS / SwiftUI)

> Arkitekturbeslut för N-back-appen. LLM:en ska följa detta i all genererad kod.

## 1. Arkitektur: MVVM

En "god class" som gör allt är **inte tillåten**. Ansvar delas så här:

| Lager | Ansvar | Får INTE |
|-------|--------|----------|
| **Model** | Ren logik och data: sekvensgenerator, poängberäkning, inställnings- och poängentiteter, lagring. | Importera SwiftUI. |
| **ViewModel** | `ObservableObject` (eller `@Observable`) som håller spelets state, tillståndsmaskinen, timern, tar emot användarhändelser (`startRound()`, `registerMatchPress()`), anropar Model och `SpeechService`. | Navigera, referera till vyer, skapa `View`s. |
| **View** | SwiftUI-vyer som ritar UI utifrån state, skickar händelser till ViewModel, sköter navigering (`NavigationStack`) och animationer. | Innehålla spellogik eller räkna poäng. |

### Föreslagen fil- och klassindelning

```
Model/
  NBackSequenceGenerator.swift  – struct; genererar sekvenser med injicerbar RandomNumberGenerator
  ScoreCalculator.swift         – ren funktion/struct för poängformeln
  GameSettings.swift            – struct: n, eventDuration, eventsPerRound, gridSize, letterCount, stimulusMode
  StimulusMode.swift            – enum: visual, audio, dual
  GamePhase.swift               – enum: idle, running, finished
  SettingsStore.swift           – läser/skriver GameSettings i UserDefaults
  ScoreEntry (Core Data)        – entitet: name, score, date (+ ev. n, mode)
  ScoreRepository.swift         – Core Data: save, fetch sorterat med NSSortDescriptor
  PersistenceController.swift   – NSPersistentContainer-setup
Audio/
  SpeechService.swift           – wrapper runt AVSpeechSynthesizer; skapas EN gång,
                                  speak(letter:), stop(), isVoiceAvailable
ViewModel/
  GameViewModel.swift           – state machine, timer, match-hantering, HUD-state
  HomeViewModel.swift           – high score + nuvarande inställningar
  SettingsViewModel.swift       – redigering av inställningar
  ScoreHistoryViewModel.swift   – lista + sorteringsval
View/
  HomeView, GameView, SettingsView, ScoreHistoryView
  GridView, MatchButton (med feedback-animation)
NBackAppTests/
  NBackSequenceGeneratorTests, ScoreCalculatorTests, GameViewModelTests
```

### Regler

- **Testbar logik separeras från UI.** `NBackSequenceGenerator`, `ScoreCalculator` och guard-logiken i `GameViewModel` ska kunna testas med XCTest utan att starta UI.
- **Beroenden injiceras via init** (slumpkälla, `SpeechService`-protokoll, `SettingsStore`, `ScoreRepository`) så att de kan bytas mot fakes i tester. Definiera protokoll, t.ex. `protocol SpeechSpeaking { func speak(_ letter: String); func stop() }`.
- **Seedbar slump:** egen `struct SeededGenerator: RandomNumberGenerator` för deterministiska tester.
- **ViewModel navigerar aldrig.** Den exponerar state (`phase == .finished`); vyn bestämmer navigeringen.
- **Observerbart state** deklareras som `@Published private(set) var` i ViewModel och prenumereras via `@StateObject`/`@ObservedObject` (eller `@State` + `@Observable`) i vyn.
- ViewModels markeras `@MainActor`.
- **En enda sanningskälla** för spel-state; vyn har bara lokalt UI-state (t.ex. `@State var isShaking`).
- **I/O utanför main thread** där det behövs: Core Data-skrivningar i `container.performBackgroundTask` eller `newBackgroundContext()`.

## 2. Tillståndsmaskin

```
idle ──startRound()──▶ running ──(sista eventet passerat)──▶ finished
  ▲                       │                                     │
  └──stopRound()──────────┘ (timer + TTS avbryts)               │
                          ◀─────────────startRound()────────────┘
```

- Varje övergång sker i **en namngiven metod** i `GameViewModel`.
- Timern körs som `Task` med `try await Task.sleep(for: eventDuration)` i en loop; referensen sparas i `private var roundTask: Task<Void, Never>?`.
- Vid `.finished` och vid `stopRound()` (anropas från `GameView.onDisappear`): `roundTask?.cancel()`, `speechService.stop()`, räkna sista missen, spara high score.

## 3. Event-tick (ordning)

1. Utvärdera föregående event: om det var match och inget tryck → `misses += 1`.
2. Avancera `currentEventIndex`.
3. Om index == eventsPerRound → `finishRound()` och returnera.
4. Visa stimulus (sätt `highlightedCellIndex`).
5. Läs upp bokstav (om auditivt läge).
6. Nollställ `hasRespondedThisEvent` (per modalitet vid dual).
7. Uppdatera HUD-state.

## 4. Namngivning (Swift API Design Guidelines)

- Namn ska **beskriva syftet**: `currentEventIndex`, inte `i`; `generateSequence(length:n:)`, inte `gen()`; `isMatchPressAllowed`, inte `check()`.
- Booleaner börjar med `is/has/can/should`.
- Typer i `UpperCamelCase`, metoder/egenskaper i `lowerCamelCase`, enum-fall i `lowerCamelCase`.
- Konstanter för magiska tal: `static let defaultMatchProbability = 0.3`, `static let minimumTouchTarget: CGFloat = 44`, `static let phoneticLetters = [...]`.

## 5. Dokumentation

- **Varje typ** har en `///`-kommentar med syfte och ansvar.
- **Publika metoder** dokumenteras med `///` inkl. `- Parameters:`, `- Returns:` och sidoeffekter.
- Icke-uppenbara beslut kommenteras med *varför* (bokstavsmängden, poängformelns vikter, varför de första n eventen är uteslutna).
- Referera krav-ID från `SPEC.md` där det hjälper, t.ex. `// SEQ-03: first n events can never match`.
- Använd `// MARK: -` för att dela upp större filer.

## 6. Tester (XCTest)

- Testklasser speglar typnamn: `NBackSequenceGeneratorTests`, `ScoreCalculatorTests`, `GameViewModelTests`.
- Testnamn beskriver beteende: `testMatchPressTwiceOnSameEventCountsOnlyOnce`.
- Slumpbaserade tester körs med `SeededGenerator` **eller** över många seeds med toleransintervall.
- För att testa `GameViewModel` utan riktig tid: exponera en intern metod `advanceToNextEvent()` som timern anropar, så testet kan driva ticks manuellt. Använd en `FakeSpeechService`.
- Testa `@MainActor`-ViewModel med `@MainActor`-markerade testmetoder.

## 7. UI-principer

- Rutnätet hålls **kvadratiskt**: `.aspectRatio(1, contentMode: .fit)`, eventuellt inom `GeometryReader` för att ta `min(width, height)`.
- Landskap vs. porträtt: välj `HStack`/`VStack` utifrån `@Environment(\.verticalSizeClass)` eller `GeometryReader`.
- Matchknapp(ar) `.frame(minWidth: 44, minHeight: 44)` (gärna större); respektera safe areas (använd inte `.ignoresSafeArea()` på innehåll).
- Feedback vid fel: kort, mjuk animation med `withAnimation` (t.ex. knappen tonar orange eller skakar lätt) – aldrig dömande text eller ljud.
- Lägg till `.accessibilityLabel` på matchknappar och rutor.
