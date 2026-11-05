# SpotGear

Osobní sbírka spatřených aut jako fotokarty. Nativní iOS aplikace (SwiftUI, SwiftData, Vision, Core ML), která funguje celá offline — bez účtu, serveru a API klíče.

Rozsah této verze je MVP podle [SpotGear/MVP.md](SpotGear/MVP.md); směr produktu popisuje [SpotGear/PROJECT.md](SpotGear/PROJECT.md).

## Stav identifikace

**Automatické návrhy značky a modelu běží lokálně přes Apple Intelligence (iOS 27+).** Viz [ADR 0002](Docs/ADR/0002-identifikace-systemovym-modelem.md).

- `SystemModelVehicleIdentifier` posílá výřez auta systémovému jazykovému modelu v zařízení (Foundation Models, obrazový vstup) a dostane nejvýše tři návrhy značka/model/generace. Žádná síť, Private Cloud Compute ani API klíč. Návrh jen předvyplní formulář; potvrzuje vždy uživatel.
- Dedikovaný klasifikátor není přítomen. Core ML adaptér (`CoreMLVehicleIdentifier`) hledá v bundlu volitelný `VehicleClassifier.mlmodelc` + `VehicleClassifier.manifest.json`; pokud by byl dodán, má přednost.
- Na iOS 17–26, zařízení bez Apple Intelligence, s vypnutou Apple Intelligence nebo během přípravy modelu aplikace zobrazí konkrétní důvod a nabídne ruční vyplnění.
- Odstranění pozadí používá `VNGenerateForegroundInstanceMaskRequest` (iOS 17+). Z více instancí ve výřezu se vybere jasně dominantní, centrální auto (`ForegroundInstancePicker`); výřez se ořízne na obrys auta. `CutoutEnhancer` pak lokálně přes Core Image jen jemně upraví černý/bílý bod (stejně pro všechny kanály, odstín se nemění, max. zesílení ~1,25×) a mírně doostří. Karta „Studio“ zobrazí výřez na studiovém pozadí ve SwiftUI (`StudioStage`) se stínem a slabým odrazem; samotné auto se nijak nedokresluje. Když maska chybí, jsou dvě srovnatelně velké instance nebo request selže (typicky v simulátoru), karta použije obyčejný fotografický výřez.
- **Hledání aut je automatické** (`VisionVehicleDetector`, [ADR 0004](Docs/ADR/0004-detekce-aut-a-katalog-cen.md)): instance popředí navrhnou rámečky a klasifikace Vision ponechá auta. Nalezená auta jdou rovnou ke kontrole, ruční výběr zůstává jako fallback. Zakrytá auta v pozadí se často nenajdou. V simulátoru tyto Vision požadavky nefungují, takže se tam používá ruční výběr; detekci je nutné zkoušet na zařízení.
- **Cena a údaje o autě** pocházejí z lokálního katalogu `Resources/VehicleCatalog.json`, ne z AI: systémový model si v měření ceny vymýšlel. Rozpětí jsou hrubé odhady pro typ auta, neověřené proti aktuálním inzerátům. Auta mimo katalog dostanou nanejvýš cenovou kategorii od systémového modelu.
- Debug sestavení nabízí „Testovací fotografii“ (`SpotGear/tesla.jpeg`, v Release vyřazená) a launch argumenty pro UI testy. Release sestavení tyto providery neobsahuje.

## Požadavky

- Xcode 27.0 (27A266a), iOS SDK 27.0
- Deployment target: **iOS 17.0**, pouze iPhone
- Žádné externí závislosti, žádný developer účet pro build do simulátoru

## Otevření, build a testy

Otevřete `SpotGear.xcodeproj`, zvolte schéma **SpotGear** a simulátor iPhone.

Pro náhled přímo v Xcode otevřete `SpotGear/App/RootView.swift` a zapněte **Editor → Canvas**
(⌥⌘↩). V Canvasu spusťte náhled **SpotGear – Sbírka** tlačítkem Resume/Restart.
Náhled používá databázi v paměti a vlastní dočasný adresář médií; začíná prázdnou sbírkou.
V interaktivním náhledu lze přes **+ → Testovací fotografie** vyzkoušet import.

```bash
xcodebuild -project SpotGear.xcodeproj -scheme SpotGear -destination 'generic/platform=iOS Simulator' build-for-testing CODE_SIGNING_ALLOWED=NO
```

```bash
xcodebuild -project SpotGear.xcodeproj -scheme SpotGear -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Pokud `xcode-select` ukazuje na Command Line Tools, předřaďte příkazu `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

Testy:

- `SpotGearTests` (Swift Testing): doména (crop, geometrie, validace, hledání), ImageIO (EXIF orientace, odstranění metadat, poškozený soubor), souborové úložiště (commit/rollback, úklid sirotků, bezpečné cesty, nedostatek místa), SwiftData na disku (znovuotevření, sdílený zdroj, delete rules, rollback při chybě), stavový model importu (zastaralé výsledky, dvojí uložení, opakování po chybě, cancel).
- `SpotGearUITests`: offline import dvou aut, neznámé auto, hledání, oblíbené, úprava, mazání, opakování po chybě uložení, testovací návrhy.

Launch argumenty (jen DEBUG): `-ui-testing` (izolovaný adresář dat), `-ui-reset`, `-ui-fake-identifier`, `-ui-fail-first-save`.

## Kde jsou data

- Databáze: `Application Support/SpotGear/SpotGear.store` (SwiftData, verzované schéma V1, bez CloudKitu).
- Média: `Application Support/SpotGear/Media/` — `assets/` (normalizované zdroje bez metadat, max. 4096 px), `derived/` (náhledy karet, výřezy bez pozadí), `staging/` (rozpracované importy).
- Data zůstávají v zařízení. Mohou být součástí systémové zálohy (iCloud / počítač). **Odinstalování aplikace sbírku smaže.**
- Databáze, kterou nelze otevřít, se nikdy automaticky neresetuje; aplikace zobrazí chybovou obrazovku.

## Fallbacky

| Situace | Chování |
|---|---|
| Chybí klasifikátor / chybný manifest | Systémový model, pokud je dostupný; jinak stav nedostupnosti a ruční formulář |
| iOS < 27, zařízení bez Apple Intelligence, vypnutá AI, model se připravuje | Konkrétní vysvětlení, ruční formulář |
| Model auto nerozpozná / odmítne snímek | „Žádné návrhy“, ruční formulář |
| Segmentace nepodporována / více objektů / prázdná maska | Fotografický výřez |
| Kamera nedostupná nebo zamítnutá | Nabídka knihovny fotografií, odkaz do Nastavení |
| Fotka jen na iCloudu offline, poškozený soubor, málo místa | Konkrétní vysvětlení a návrat k výběru |
| Chyba uložení | Rollback DB i souborů, návrat k souhrnu, opakování bez duplicit |
| Chybí náhled karty | Regenerace ze zdroje; chybí-li zdroj, „Fotografie není dostupná“ |
| Pád během importu | Při dalším startu se smaže staging a nereferencované soubory |

## Architektura

```text
SpotGear/
  App/              composition root (AppServices), RootView, launch options, debug fixtures
  Domain/           hodnotové typy bez SwiftUI/Vision/SwiftData (CropRect, identita, stav regionu)
  Application/      porty (MediaStore, VehicleIdentifier, ForegroundSegmenter, SpotRepository),
                    ImportSession (@MainActor stavový model), SpotLibrary (use-casy nad sbírkou)
  Features/         Collection, Capture, ImportReview, SpotDetail, Settings
  Infrastructure/   Persistence (SchemaV1, repository), Media (ImageIO, soubory, worker),
                    Vision (segmentace), CoreML (adaptér klasifikátoru),
                    FoundationModels (návrhy systémovým modelem v zařízení)
  DesignSystem/     sdílené komponenty karet a formuláře
  Resources/        String Catalog (výchozí čeština)
SpotGearTests/      unit + integrační testy
SpotGearUITests/    UI testy
TestFixtures/       popis syntetických fixtures
Docs/ADR/           rozhodnutí
```

Rozhodnutí jsou v [Docs/ADR](Docs/ADR).

## Stav acceptance criteria

Legenda: **Ověřeno testem (simulátor)** = test skutečně spuštěn a prošel; **Implementováno, neověřeno** = kód a test existují, ale nebyly spuštěny; **Manuální** = vyžaduje fyzické zařízení.

28. 10. 2026 byly spuštěny všechny testy v simulátoru iPhone 18 Pro (iOS 27.0): 60 unit/integračních testů a 4 UI testy prošly. Fyzické zařízení ověřeno nebylo.

| ID | Stav | Pokrytí |
|---|---|---|
| AC01 | Ověřeno testem (simulátor) | `CoreMLVehicleIdentifierTests`; nedostupnost systémového modelu kryje `SystemModelVehicleIdentifierTests`, v simulátoru byl ale model dostupný, takže tato větev neběžela |
| AC02 | Implementováno, neověřeno | žádná síťová API; UI test `testOfflineImport…` |
| AC03 | Ověřeno testem (simulátor) | `threeRegionsSaveAsThreeSpotsWithOneSharedSource` |
| AC04 | Ověřeno testem (simulátor) | `unavailableIdentifierProducesNoSuggestions` |
| AC05 | Ověřeno testem (simulátor) | `identityCanBeCompletedAndClearedLater`, UI test |
| AC06 | Ověřeno testem (simulátor) | `suggestionsAreNeverSavedWithoutConfirmation` |
| AC07 | Ověřeno testem (simulátor) | `cropChangeDuringProcessing…`, `staleResultIsIgnored` |
| AC08 | Ověřeno testem (simulátor) | `exifOrientationIsApplied…`, `cropAfterOrientation…` |
| AC09 | Ověřeno testem (simulátor) | `cancelRemovesStagingAndSavesNothing`, sweep test |
| AC10 | Ověřeno testem (simulátor) | `doubleSaveCreatesOneBatch`, `failedSaveKeepsCollection…` |
| AC11 | Ověřeno testem (simulátor) | `failedSaveKeepsCollection…`, `lowDiskSpace…` |
| AC12 | Ověřeno testem (simulátor) | `deletingOneOfThree…`, `libraryDeletionRemovesFiles…` |
| AC13 | Ověřeno testem (simulátor) | `threeSpotsShareOneAssetAndSurviveReopen` |
| AC14 | Manuální | ovládání regionů tlačítky + VoiceOver akce; ověřit na zařízení |
| AC15 | Manuální | sémantické barvy, bez nutných animací |
| AC16 | Manuální | kamera/iCloud nutno ověřit na zařízení |
| AC17 | Ověřeno testem (simulátor) | `missingThumbnailIsRegenerated…`, `StoreErrorView` |
| AC18 | Ověřeno testem (simulátor) | `SearchTextTests`, UI test hledání |
| AC19 | Ověřeno testem (simulátor) | `deleteAllEmptiesTheStore…` |

Zbývá: manuální ověření na zařízení (kamera, oprávnění, Vision segmentace, režim letadlo, VoiceOver, největší písmo, dark mode, Reduce Motion, 10 regionů, měření paměti a doby importu) a snímky obrazovek z reálného běhu.

## Známá omezení

- Návrhy vyžadují iOS 27 a Apple Intelligence; přesnost systémového modelu pro auta nebyla změřena (ověřen jen jeden snímek: Tesla → „Tesla Model 3“ v simulátoru iOS 27).
- Dedikovaný klasifikátor aut s licencí a model card zatím není.
- Normalizovaný zdroj je zmenšen na 4096 px delší strany; plné rozlišení originálu se neukládá.
- Výřez uloženého spotu nelze dodatečně upravit (mimo rozsah MVP).
- Rozpracovaný import se po ukončení aplikace neobnovuje (staging se při dalším startu uklidí).
- Segmentace v simulátoru typicky není dostupná — karta pak použije fotografický výřez.

## Vzhled a licence písem

RPG vzhled a pixelové karty popisuje [ADR 0003](Docs/ADR/0003-rpg-design-a-pixel-art.md). Přibalená písma Pixelify Sans a Press Start 2P jsou pod licencí SIL Open Font License; texty licencí jsou v `SpotGear/Resources/Fonts`.
