# CONTEXT.md – Kursspecifika ramar (iOS)

> Ramvillkor från kursen HI1033 / CM2023, Lab B:1. LLM:en ska hålla sig inom dessa.

## 1. Kursregler

- **Individuell uppgift.** Kopiera inte någon annans lösning (AI-genererad eller ej).
- Labben måste vara godkänd innan Lab B:2 och B:3.
- **Muntlig examination:** studenten måste kunna förklara **varje kodrad**, oavsett om den skrivits av människa eller AI. → Generera hellre enkel, läsbar kod än smart och kompakt kod.
- All AI-assistans ska redovisas. All AI-genererad kod ska verifieras och testas av studenten.

## 2. Tekniska begränsningar

- **Plattform:** iOS, Swift, SwiftUI, Xcode.
- **Inga externa bibliotek** (inga Swift Packages/CocoaPods) – endast Apples ramverk: SwiftUI, Foundation, AVFoundation, Core Data, XCTest.
- **Sekvenslogiken får inte delegeras till ett bibliotek** – den ska vara egen kod.
- **Få filer, men inte en god class.** Kursens rekommendation är "single-file preferred", men MVVM-kravet går före: håll antalet filer litet, men behåll separata typer för Model, ViewModel och View (se `STYLE.md`).
- Kod och identifierare på engelska; kommentarer får vara på engelska eller svenska (var konsekvent).

## 3. iOS-API:er att använda

| Område | API |
|---|---|
| UI | SwiftUI, `NavigationStack` för navigering |
| Observerbart state | `ObservableObject` + `@Published` (prenumereras med `@StateObject`/`@ObservedObject`), alternativt `@Observable` |
| TTS | `AVSpeechSynthesizer` – skapas **en gång** (i `SpeechService`), `speak(AVSpeechUtterance(string:))` per event, `stopSpeaking(at: .immediate)` vid stopp |
| Röst saknas | `AVSpeechSynthesisVoice(language: "en-US") == nil` → visa fallback-meddelande, kör ändå visuellt |
| Ljudsession | `AVAudioSession.sharedInstance().setCategory(.playback)` så att tal hörs även med ljudlös-knappen på |
| Inställningar | `UserDefaults` (eller `@AppStorage` i vyer – men logiken går via `SettingsStore`) |
| Poängdatabas | Core Data, `NSFetchRequest` med `NSSortDescriptor` (namn, poäng, datum) |
| Timer | `Task` + `Task.sleep(for:)`, avbryts med `task.cancel()`; anropas från `.onDisappear` |
| Bakgrundsarbete | `container.performBackgroundTask` / `newBackgroundContext()`; UI-uppdateringar på `@MainActor` |
| Tester | XCTest (unit test-target) |
| Testa på | iPhone- och iPad-simulator, porträtt och landskap |
| Min touch-target | 44 × 44 pt (Apple Human Interface Guidelines) |

## 4. Saker LLM:en ofta gör fel – kontrollera särskilt

- Låter icke-match-events **råka** matcha (ingen aktiv undvikning) → för hög matchfrekvens.
- Tillåter match under de första n eventen eller efter rundans slut.
- Glömmer att räkna **misses** vid tysta ticks (endast tryck räknas).
- `Timer`/`Task` och TTS fortsätter efter att spelaren lämnat skärmen (saknar `.onDisappear` → `stopRound()`).
- Skapar en ny `AVSpeechSynthesizer` per event, eller som lokal variabel (den deallokeras och tystnar).
- Lägger navigering eller `View`-referenser i ViewModel.
- Skriver all logik i en enda `View` (god class).
- Poängen kan bli negativ.
- Använder `Timer.scheduledTimer` utan att invalidera den, eller fångar `self` starkt i closures.
- Glömmer `@MainActor` → UI-uppdateringar från bakgrundstråd.
- Tester som inte går att köra eller som testar UI i stället för logik.

## 5. Muntlig examination – koden ska göra detta lätt att visa

Organisera koden så att följande går att peka ut snabbt (frågelistan finns i labbinstruktionen):

- Sekvensgenerering, matchfrekvens, första-n-garanti + tester för dem
- Tillståndsmaskinen och alla övergångar
- En event-tick från början till slut
- Guards mot för tidigt/sent tryck och dubbeltryck + tester
- Var hits/misses/false alarms räknas; poängformeln och varför den inte blir negativ
- Var timern avbryts; vad som händer när man lämnar skärmen
- Observerbart state: var `@Published` deklareras och var det prenumereras
- TTS-initiering, bokstavsmängd, beteende utan röst; varför tal startar först efter användarens tryck
- Inställningar: en skrivning och en läsning i `UserDefaults`; Core Data-entiteten och en sorterad fetch
- Kvadratiskt rutnät i alla orienteringar; touch-target och safe areas
- Vilka delar som är AI-genererade (första frågan, nr 26)
