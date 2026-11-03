# SPEC.md – N-back-app (Lab B:1, HI1033 / CM2023)

> Ge denna fil till LLM:en i början av varje session tillsammans med `STYLE.md` och `CONTEXT.md`.
> Varje krav har ett ID (t.ex. `F-03`) så att prompter, kod-kommentarer och tester kan referera till det.

## 1. Mål

En native mobilapp som implementerar **N-back** – ett arbetsminnestest. En sekvens av stimuli visas en i taget; spelaren trycker på en knapp när aktuellt stimulus matchar det som visades **exakt n steg tidigare**.

- **Visuellt stimulus:** en markerad ruta i ett rutnät (3×3 som standard).
- **Auditivt stimulus:** en uppläst bokstav (text-to-speech).
- **Dual n-back:** båda sekvenserna samtidigt och oberoende av varandra; spelaren bevakar båda.

## 2. Plattform

**Vald plattform:** iOS – Swift, SwiftUI, Xcode. Testas på iPhone- och iPad-simulator.

Plattformen väljs innan arbetet börjar och byts inte under labben. Se `CONTEXT.md` för plattformsspecifika API:er.

---

## 3. Grundkrav – obligatoriska för godkänt (1 poäng)

### 3.1 Skärmar

| ID | Krav |
|----|------|
| S-01 | Appen har **minst två skärmar**: Hemskärm och Spelskärm. |
| S-02 | **Hemskärm** visar aktuellt **high score**. |
| S-03 | Hemskärm låter spelaren välja stimulustyp: **visuellt**, **auditivt** eller **båda**. |
| S-04 | Hemskärm visar aktuella inställningar: **stimulustyp, n, eventlängd (duration), antal events per runda**. |
| S-05 | **Spelskärm** visar **3×3-rutnätet** för visuella stimuli och/eller spelar upp bokstäver för auditiva stimuli. |
| S-06 | Spelskärm visar live-state (HUD): **aktuellt eventnummer** och **antal korrekta svar hittills**. |
| S-07 | Spelskärm har en **knapp för att starta ny runda** och en **knapp för att registrera n-back-match**. |

### 3.2 Stimuli

| ID | Krav |
|----|------|
| ST-01 | Visuellt: rutnät 3×3, **exakt en ruta markerad per event**. |
| ST-02 | Auditivt: upplästa bokstäver från en **fast, fonetiskt distinkt mängd** (t.ex. `C, H, K, L, Q, R, S, T` – undvik förväxlingsbara som B/D/P/V/E/G). |
| ST-03 | Bokstavsmängden definieras på **ett ställe** i koden (konstant) med kommentar om varför just de bokstäverna valts. |

### 3.3 Sekvenslogik (ska vara egenimplementerad – inte delegerad till bibliotek)

| ID | Krav |
|----|------|
| SEQ-01 | En funktion genererar hela sekvensen för en runda och returnerar en lista med stimulusindex (en lista per modalitet vid dual). |
| SEQ-02 | **Matchfrekvens ~20–40 %**: för varje event från index `n` och framåt avgörs med en sannolikhet (t.ex. 30 %) om eventet ska vara en match. Platsen där sannolikheten avgörs ska vara tydlig i koden. |
| SEQ-03 | **De första n eventen kan aldrig vara matchningar.** (Index `0..n-1` har inget n-steg-bakåt att jämföra med.) |
| SEQ-04 | När ett event *inte* ska vara en match måste genereringen **aktivt undvika** att det råkar bli en (välj ett värde ≠ värdet `n` steg bakåt). Annars blir den faktiska matchfrekvensen högre än avsett. |
| SEQ-05 | Sekvensgeneratorn ska kunna ta en **injicerbar slumpkälla / seed** så att den kan testas deterministiskt. |
| SEQ-06 | Vid dual n-back genereras visuell och auditiv sekvens **oberoende** av varandra. |

### 3.4 Spellogik och livscykel

| ID | Krav |
|----|------|
| G-01 | Spelet har en explicit **tillståndsmaskin**: `Idle → Running → Finished` (och `Finished → Running` vid ny runda). Alla övergångar ska gå att peka ut i koden. |
| G-02 | En **event-tick**: avancera sekvensen → visa stimulus (markera ruta) → läs upp bokstav → nollställ match-flagga → uppdatera HUD. |
| G-03 | Rundan är slut när antal events per runda är uppnått; då körs cleanup och tillståndet blir `Finished`. |
| G-04 | Ett matchtryck **ignoreras** (a) innan rundan startat, (b) efter att den avslutats, (c) under de första n eventen. |
| G-05 | **Flera matchtryck på samma event ignoreras efter det första** (double-press prevention). |
| G-06 | **Rundans timer avbryts rent** när rundan tar slut **och** när spelaren lämnar skärmen mitt i en runda (ingen timer eller TTS fortsätter i bakgrunden). |
| G-07 | Tal (TTS) startas först efter en **användarinteraktion** (t.ex. tryck på Start). |

### 3.5 Poäng och feedback

| ID | Krav |
|----|------|
| P-01 | Följande räknas: **hits** (tryck vid match), **false alarms** (tryck utan match), **misses** (match utan tryck – räknas vid den "tysta" ticken när eventet passerar). |
| P-02 | **Poängformel** är definierad på ett ställe och dokumenterad. Förslag: `score = max(0, hits − falseAlarms)` (eller viktad variant, t.ex. `2·hits − falseAlarms − misses`, clampad till ≥ 0). Vikterna ska kunna motiveras. |
| P-03 | Poängen kan **aldrig bli negativ**. |
| P-04 | "Korrekta svar" i HUD = antal hits (definiera och dokumentera). |
| P-05 | Vid **felaktigt matchtryck** ges **icke-kränkande animerad feedback**, t.ex. färg- eller storleksanimation på knappen (ingen text som "Fel!", inga ljud som bestraffar). |
| P-06 | High score sparas persistent och visas på hemskärmen. |

### 3.6 Enhetstester

| ID | Krav |
|----|------|
| T-01 | Enhetstester för **minst tre** av: sekvensgenerering, matchfrekvens, första-n-garantin, double-press-skydd, poängformel. |
| T-02 | Testerna ska vara **körbara och passera** på den inlämnade koden. |
| T-03 | Testerna ska testa logiklagret (ViewModel/Model) utan UI. |
| T-04 | Rekommenderat: ett test som **fallerar om double-press-guarden tas bort** (muntlig fråga 28). |

#### Förslag på testfall (XCTest)
- `testSequenceHasRequestedLength`
- `testFirstNEventsAreNeverMatches` (kör med många seeds)
- `testMatchRateIsWithin20To40Percent` (stort antal events/flera körningar)
- `testNonMatchEventsDoNotAccidentallyMatch`
- `testMatchPressBeforeStartIsIgnored`
- `testMatchPressAfterFinishIsIgnored`
- `testMatchPressDuringFirstNEventsIsIgnored`
- `testMatchPressTwiceOnSameEventCountsOnlyOnce`
- `testScoreIsNeverNegative`
- `testScoreFormulaCountsHitsAndFalseAlarmsCorrectly`

---

## 4. Högre nivå – för full poäng (2 poäng)

Krav: **dual n-back** + **minst tre** av H-02…H-05.

| ID | Krav |
|----|------|
| H-01 | **Dual n-back**: visuellt och auditivt samtidigt. **Två separata matchknappar** (en för position, en för ljud), varsin match-flagga, varsin poängräkning. |
| H-02 | **Inställningsskärm (persistent)**: antal events per runda, eventlängd, värde på n, rutnätsstorlek (t.ex. 3×3/4×4/5×5), antal distinkta bokstäver. Inställningarna överlever omstart av appen. |
| H-03 | **Poänghistorik**: spelaren sparar poäng under ett namn; separat skärm listar alla poäng **sorterbara på namn, poäng och datum**. Lagras i en **lokal databas** (sorteringen görs i query:n). |
| H-04 | **Responsiv layout**: fungerar i **porträtt och landskap**, på **telefon och surfplatta**. Rutnätet förblir kvadratiskt. |
| H-05 | **Tillgänglighet**: matchknappen uppfyller **minsta touch-target** (≥ 44×44 pt); **fallback-meddelande** visas om ingen TTS-röst finns (`AVSpeechSynthesisVoice(language:)` returnerar `nil`). Safe areas respekteras. |

---

## 5. Inlämning (utanför koden men krav)

1. **Kod** – hela projektet, MVVM (MVC ok), dokumenterad, beskrivande namn.
2. **LLM-processdokument** (~1 sida): verktyg, kontextfiler (bifoga SPEC.md, STYLE.md, CONTEXT.md), 2–3 representativa prompter + vad de gav, vad LLM:en gjorde fel som du rättade.
3. **Testrapport**: vilka delar som testats, vilka testfall, resultat. Bifoga testfilerna.
4. **Reflektion** (~½ sida): en sak som överraskade med AI-arbetet, en sak du gör annorlunda nästa gång.

Lämnas in **minst en dag före** redovisningen.

## 6. Acceptanskriterier (checklista)

- [ ] Hem- och spelskärm finns (S-01…S-07)
- [ ] 3×3-rutnät, en ruta per event; fonetiskt distinkta bokstäver (ST-01…ST-03)
- [ ] Egen sekvensgenerator: 20–40 % match, första n aldrig match (SEQ-01…SEQ-06)
- [ ] Tillståndsmaskin Idle/Running/Finished (G-01)
- [ ] Matchtryck ignoreras före/efter runda och under första n (G-04)
- [ ] Dubbeltryck ignoreras (G-05)
- [ ] Timer avbryts vid rundslut och när skärmen lämnas (G-06)
- [ ] Icke-kränkande animerad feedback vid fel (P-05)
- [ ] Poäng aldrig negativ (P-03)
- [ ] ≥ 3 enhetstester som passerar (T-01, T-02)
- [ ] Dual n-back + minst tre av H-02…H-05 (för full poäng)
