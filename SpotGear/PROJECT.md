# SpotGear — vize a architektura projektu

Verze 1.0 · 28. října 2026 · iOS aplikace pro osobní sbírku spatřených aut

Tento dokument popisuje směr produktu. Závazný rozsah první implementace určuje [MVP.md](MVP.md). Budoucí funkce zde nejsou požadavkem na MVP.

## 1. Produktová myšlenka

SpotGear promění vlastní fotografie aut v osobní sbírku fotokaret. Uživatel auto vyfotí nebo importuje snímek, aplikace na něm sama najde jedno či více aut, uživatel zkontroluje návrhy identifikace a uloží každé vybrané auto jako samostatný spot. Kolekce má připomínat sběratelský katalog, ale zůstává věrným záznamem skutečných pozorování.

Hlavní hodnota je radost z objevování, přehledná historie a kvalitní prezentace vlastních fotografií. Automatická identifikace je pomocník, nikoli podmínka použitelnosti ani autorita.

### Základní principy

- Local-first: fotografie, databáze i inference zůstávají v zařízení; hlavní cesta funguje bez účtu a internetu.
- Uživatel rozhoduje: AI nikdy sama nepotvrdí značku, model, generaci ani rok.
- Nejistota je přípustná: „Neznámé auto“ je plnohodnotný záznam.
- Jedna fotografie může obsahovat více aut; jedno pozorování může později obsahovat více fotografií stejného auta.
- Zachovat skutečný vzhled: karty používají fotografii nebo její výřez. Generované pohledy nejsou důkazem skutečné podoby.
- Rozšiřitelnost přes stabilní pojmy a datové kontrakty, nikoli přes předčasné frameworky a abstrakce.

## 2. Funkce a hranice produktu

| Oblast | MVP | Pozdější produkt |
|---|---|---|
| Vstup | Fotoaparát, jedna fotografie z PhotosPicker | Více fotografií jednoho spotu, video a výběr snímků |
| Více aut | Automatická detekce systémovým Vision, ruční oblasti jako fallback | Kvalitnější detektor i pro zakrytá auta |
| Identifikace | Ruční údaj, neznámé auto; lokální návrhy pouze s použitelným modelem; orientační cena a údaje z lokálního katalogu | Kvalitnější modely, širší katalog a vícepohledová evidence |
| Fotokarta | Pixelová karta, fotografický výřez; pokus o lokální odstranění pozadí | Šablony, další stylování a export |
| Kolekce | Přehled, detail, hledání, oblíbené, oprava a mazání, XP, úrovně a výzvy | Statistiky, album, filtr generací |
| Data | SwiftData a soubory v sandboxu | Přenosný export/import, volitelná synchronizace |
| Sociální funkce | Žádné | Pouze po samostatném návrhu soukromí a moderace |

### Explicitní non-goals

MVP neobsahuje 3D rekonstrukci, generování dalších pohledů, vlastní trénování modelu, kompletní automobilový katalog, živou detekci ve videu, cloud, účet, mapy, polohu, SPZ/OCR, sociální síť ani monetizaci. Produkt neslouží k identifikaci majitele vozidla, ověřování identity konkrétního vozu ani k určování ceny konkrétního kusu nebo autenticity. Orientační rozpětí z katalogu popisuje typ auta ([ADR 0004](../Docs/ADR/0004-detekce-aut-a-katalog-cen.md)).

„Bez placeného API“ znamená bez povinných poplatků za inference a bez serverové závislosti. Neznamená nulové náklady na zařízení, vývoj, případnou distribuci či získání licencovaných dat a modelů.

## 3. Realistická lokální AI

Je nutné rozlišovat tři úlohy:

1. **Detekce** navrhne obdélníky obsahující auta. Vyžaduje odpovídající detektor, nelze ji zaměnit za obecnou klasifikaci obrázku.
2. **Segmentace** oddělí vybraný objekt od pozadí. Vision poskytuje segmentaci výrazných objektů, ale její instance nemusí odpovídat jednotlivým autům. Může spojit překrývající se objekty nebo některé vynechat.
3. **Identifikace** navrhne značku/model z výřezu. Pro automobilové modely je nutný vhodný klasifikátor a mapování jeho tříd. Samotné Core ML ani obecné štítky Vision nedodávají katalog značek a modelů.

Žádný konkrétní externí model není v tomto zadání považován za dostupný či licenčně schválený. Základní build musí fungovat bez něj. Zabudovaný model musí mít doloženou licenci k distribuci vah i labelů, kompatibilní vstup/výstup a změřené chování na cílovém zařízení. Detektor, segmentátor a klasifikátor mají nezávislé capability stavy.

### Politika nejistoty a fallbacků

| Situace | Chování |
|---|---|
| Chybí detektor nebo nenajde auto | Uživatel přidá a upraví obdélník ručně |
| Auto není v katalogu | Žádná cena ani údaje; nanejvýš označená hrubá cenová kategorie z modelu |
| Chybí klasifikátor, inference selže nebo nepodporuje dané auto | Formulář pro značku/model; možnost uložit neznámé |
| Několik podobných návrhů | Nejvýše tři kandidáti a „Žádný z návrhů“ |
| Chybí rozumná maska nebo obsahuje více objektů | Nabídnout obyčejný výřez; uživatel přepne vzhled |
| Model není schopen rozlišit generaci/rok | Pole ponechat prázdné; neodvozovat z vymyšlených pravidel |
| Simulator či zařízení danou operaci nepodporuje | Skutečný capability stav; žádná simulovaná úspěšná AI v produkci |

Skóre modelu není pravděpodobnost správné identifikace. Uživateli neslibovat procenta přesnosti. Případné prahy musí vzniknout vyhodnocením konkrétního modelu na relevantních datech; univerzální práh se nestanovuje. Kandidáti se nesmějí automaticky měnit na potvrzená fakta.

Kvalitu budoucích modelů vyhodnocovat odděleně pro den/noc, rozmazání, úhel pohledu, zakrytí, více aut a auta mimo katalog. Měřit záměny, schopnost odmítnout neznámé, latenci, paměť a velikost modelu. Publikovat metodiku a omezení, nikoli neověřený slib přesnosti.

## 4. Uživatelský tok a pipeline

1. Pořízení nebo výběr fotografie. PhotosPicker může odkazovat na médium pouze v iCloudu; bez lokálních dat zobrazit vysvětlení a nabídnout jiný snímek nebo fotoaparát.
2. Kopie do soukromého pracovního adresáře, kontrola dekódování, normalizace EXIF orientace a příprava menšího pracovního obrazu.
3. Automatická detekce aut. Nalezená auta jdou rovnou ke kontrole. Ruční výběr je fallback: každá oblast má vlastní ID; uživatel může přidávat, měnit nebo odstranit oblasti a přepínat mezi nimi.
4. Pro každou oblast samostatně: výřez → volitelná identifikace → ruční potvrzení nebo neznámé auto. Změna oblasti zneplatní odvozené výsledky.
5. Pokus o segmentaci vybraného výřezu. Náhled karty nabídne výřez či dostupný cutout na klidném pozadí; neúspěch neblokuje uložení.
6. Souhrn vybraných aut. Uložit vytvoří samostatný spot pro každou zahrnutou oblast a jednu sdílenou zdrojovou fotografii.
7. Kolekce a detail. Pozdější úprava identity nemění zdrojovou fotografii ani přepisem neztrácí původní návrh modelu.

Zpracování běží mimo hlavní UI executor, s omezenou souběžností a podporou zrušení. Během náročné operace je vidět stav, nikoli smyšlené procento postupu. MVP nemusí dokončit práci na pozadí po ukončení aplikace; konzistence uložených dat ale musí zůstat zachována.

## 5. Technologie a architektura

Výchozí minimum: **iOS 17**, SwiftUI, SwiftData, Vision, Core ML, PhotosUI, ImageIO/Core Graphics. Použít aktuální stabilní Xcode a do README zapsat konkrétní ověřenou verzi. Pro iOS 17 použít kompatibilní VN* API; novější Vision API nelze bez dostupnostních kontrol zavést do základní cesty.

Jedna aplikace, jeden lokální SwiftData store, žádný backend a žádná povinná třetí knihovna. SwiftData spravuje metadata; fotografie a odvozené obrazy jsou soubory, nikoli velké binární atributy databáze.

### Vrstvy

- **Features / SwiftUI:** obrazovky a úzce zaměřené stavové modely. Stav prezentace na `@MainActor`.
- **Domain:** hodnotové typy, validace, identita, pravidla výběru a potvrzení. Nezávislé na SwiftUI, Vision a SwiftData.
- **Application:** orchestrace importu, zpracování a uložení. Řídí zrušení, chyby a hranice transakcí.
- **Infrastructure:** SwiftData, soubory, Vision/Core ML a systémové foto rozhraní. Závislosti předává composition root.

Rozhraní zavádět tam, kde existuje vedlejší efekt či výměnný algoritmus: media store, spot repository, identifikátor a segmentátor. Jednoduché čisté funkce nepotřebují protokol. Test doubles použít v testech a previews, nikdy k vydávání předstíraných výsledků za lokální AI.

SwiftData modely nepřenášet mezi executory. Persistence má jednoho jasného vlastníka; používat DTO/ID na hranicích. Náročné dekódování a inference provádět ve workeru se serializovaným přístupem k modelu. Kontrolovat zrušení mezi kroky a zahazovat výsledky starší revize vstupu.

### Pravidla codebase

KISS před spekulativní flexibilitou. DRY pro skutečně sdílená pravidla, ne pro náhodně podobné obrazovky. SOLID tam, kde pomůže oddělit odpovědnosti a efekty; bez hluboké dědičnosti a univerzálních service managerů. Preferovat malé struktury, explicitní závislosti, vyčerpávající enumy a typované chyby. Žádné síťové volání v zobrazení, force unwrap v produkční cestě ani tiché polykání chyb.

## 6. Datový model

**Spot** je jedno zachycení jednoho auta, nikoli katalogový automobil ani tvrzení, že jde o unikátní fyzický vůz. Opakovaný spot stejného modelu je validní. **VehicleIdentity** je popis typu vozu. Neprovádět automatické slučování podle modelu nebo vzhledu.

### Schéma V1 — implementovat v MVP

| Entita | Hlavní pole | Vztahy a význam |
|---|---|---|
| `PhotoAsset` | UUID, createdAt, capturedAt?, relativePath, width, height, contentHash? | Jedna importovaná normalizovaná fotografie; 1:N `SpotPhoto` |
| `Spot` | UUID, createdAt, updatedAt, observedAt?, note, isFavorite, identityStatus, make?, model?, generation?, year?, identitySource?, confirmedAt? | 1:N `SpotPhoto`, 1:N `IdentificationAttempt`; identity je snapshot potvrzený uživatelem |
| `SpotPhoto` | UUID, order, isPrimary, cropX/Y/Width/Height, revision, cardStyle, renderVersion, cutoutPath?, thumbnailPath? | N:1 Spot, N:1 PhotoAsset; výřez a vzhled patří vazbě, ne sdílené fotce |
| `IdentificationAttempt` | UUID, createdAt, inputRevision, providerID, modelVersion?, labelMapVersion?, outcome, candidatesData | N:1 Spot; snapshot návrhů a jejich původu, nikoli živá reference na měnící se model |

`candidatesData` je verzovaný Codable payload s nejvýše třemi kandidáty: rawLabel, make?, model?, generation?, score?. Neznámý nebo chybný payload nesmí znemožnit čtení spotu. V MVP může být pokus uložen jen tehdy, pokud inference skutečně proběhla; nepřítomnost modelu není fiktivní pokus.

`identityStatus`: `unknown` nebo `userConfirmed`. `identitySource`: `manual` nebo `modelSuggestion`, pouze pro potvrzený popis. Potvrzeno uživatelem neznamená objektivně ověřeno. Značka může být známá bez modelu; model bez značky formulář nepřijme. Rok je volitelný ruční údaj, nikoli datum pozorování. Při „Nevím“ zůstávají identifikační pole prázdná.

### Invarianty

- UUID jsou stabilní; cesta je relativní k vlastnímu úložišti a nesmí opustit jeho kořen.
- Obdélník je normalizovaný v rozsahu 0…1, s nenulovou plochou, vůči orientovanému zdrojovému obrazu. Doménový počátek je vlevo nahoře; převod z Vision je explicitní a testovaný.
- Každý uložený spot má alespoň jednu `SpotPhoto` a právě jednu primární. MVP vytváří přesně jednu, schéma podporuje více.
- Každá vazba odkazuje na existující zdroj. Dvě auta na jedné fotografii mají dva spoty a dvě vazby ke stejnému assetu.
- Odstranění spotu odstraní jeho vazby, pokusy a odvozené soubory. Zdroj se smaže až po odstranění posledního odkazu. Nikdy necascadovat mazání vazby do sdíleného assetu.
- Odvozené soubory jsou obnovitelné; vlastní fotografie nejsou cache.

### Soubory a konzistence

Použít `Application Support/SpotGear/Media` pro vlastní fotografie a potřebné výřezy, `Caches` pro obnovitelné náhledy, dočasný staging pro import. Neukládat GPS a další nepotřebné EXIF údaje do normalizované fotografie. Zachovat vizuální obsah, nikoli původní binární soubor se všemi metadaty.

Souborový systém a SwiftData nemají společnou transakci. Nejprve připravit a atomicky přesunout soubory, potom explicitně uložit databázový batch. Při chybě rollbacknout DB a odstranit soubory vytvořené daným importem. Při pádu může zbýt osiřelý soubor: při startu provést bezpečnou kontrolu referencí a úklid dokončených/neaktivních importů. Nikdy mazat neověřené nebo právě používané soubory. Chybějící zdroj označit jako nedostupný, nezničit kvůli tomu celou databázi.

## 7. Vizuální směr a accessibility

RPG rozhraní inspirované Codédexem ([ADR 0003](../Docs/ADR/0003-rpg-design-a-pixel-art.md)): tmavá paleta, pixelové nadpisy a popisky, panely se stupňovitými rohy, segmentové progress bary a generované pixelové scény. Delší text zůstává v systémovém písmu. Karty aut jsou hlavní obsah; žádné přeplněné dashboardy ani falešné skenery. Gamifikace (XP, úrovně, výzvy) odráží jen skutečně uložené údaje.

Kolekce používá hlavičku s úrovní a adaptivní mřížku karet s poměrem obrázku 4:3, názvem a datem. Detail má velkou kartu, přepínač vzhledu, průzkum údajů, zobrazení zdroje a jasné úpravy. Podporovat tmavý vzhled, Dynamic Type a Reduce Motion. Text se nesmí ztratit kvůli pevným výškám.

Interakční plochy alespoň 44 × 44 bodů. Barva není jediným nositelem stavu. VoiceOver popíše pořadí auta, identitu, stav výběru i akce. Obdélníkový výběr musí mít vedle gest přístupnou cestu: seznam oblastí, přidání přednastavené oblasti a označené ovládání posunu/velikosti. Uživatel s VoiceOver musí dokončit import včetně více aut.

Všechny řetězce ve String Catalog. MVP české, připravené na lokalizaci; datum a čísla podle locale. Prázdné, načítací, chybové i nedostupné stavy jsou součástí návrhu.

## 8. Soukromí a provoz

MVP nemá analytiku, síťový AI fallback ani přenos fotografií. Nežádá polohu. PhotosPicker použít pro konkrétní výběr; fotoaparát žádá oprávnění až při použití. Zamítnutí nesmí zablokovat import z knihovny. Fotografie mohou obsahovat lidi a SPZ: neindexovat je a nevypisovat obrazová data či osobní metadata do logů.

Local-first neznamená automaticky vyloučení ze systémových záloh. README a nastavení mají vysvětlit, že data jsou lokální, mohou podléhat uživatelskému zálohování zařízení a odinstalace může lokální sbírku odstranit. Cloud sync a vlastní export nejsou v MVP. Přidat možnost smazat celou sbírku s potvrzením.

## 9. Projektová struktura

```text
SpotGear/
  App/                         # entry point, composition root, navigace
  Domain/                      # DTO, identity, crop geometry, pravidla
  Application/                 # ImportCoordinator, SaveImport, DeleteSpot
  Features/
    Collection/
    Capture/
    ImportReview/
    SpotDetail/
    Settings/
  Infrastructure/
    Persistence/               # SchemaV1, MigrationPlan, repository
    Media/                     # filesystem, decode, thumbnail, rendering
    Vision/                    # foreground segmentation
    CoreML/                    # optional classifier + manifest loader
  DesignSystem/                # malá sada tokenů a sdílená PhotoCard
  Resources/                   # assets, Localizable.xcstrings, model manifest
SpotGearTests/                  # pravidla, geometrie, pipeline, persistence
SpotGearUITests/                # hlavní scénáře, přístupnost
TestFixtures/                  # legální testovací snímky a metadata
Docs/                          # ADR, profilování, model card
```

Názvy jsou vodítko; nevytvářet prázdné vrstvy ani soubor pro každý triviální typ. V první verzi nejsou potřeba samostatné Swift packages.

## 10. Migrace a rozšíření

Od první verze používat `VersionedSchema` a `SchemaMigrationPlan`. Vydané schéma V1 neměnit na místě. Nové pole přidat s volitelnou hodnotou či bezpečným defaultem; pro transformace zavést testovanou migrační fázi. Při chybě migrace nikdy automaticky smazat store. Nabídnout srozumitelnou chybu, zachovat původní data a diagnostiku bez fotografií.

Verzovat zvlášť DB schéma, exportní formát, model/label map, payload kandidátů a renderer fotokarty. Aktualizace modelu nesmí přepsat potvrzené údaje ani znovu spustit celou kolekci bez akce uživatele. Při změně rendereru lze líně obnovit náhledy ze zdroje.

| Etapa | Rozšíření | Změna a podmínka dokončení |
|---|---|---|
| 0 | MVP | Kompletní offline cesta, konzistence a přístupnost podle MVP.md |
| 1 | Vhodný klasifikátor/detektor | Licence, model card, měření na zařízení, neznámé třídy a ruční override |
| 2 | Více fotografií spotu | UI nad existující SpotPhoto; explicitní připojení uživatelem, bez automatického slučování |
| 3 | Katalog | Nová VehicleDefinition se stabilním ID a volitelná vazba ze Spot; zachovat uživatelský snapshot |
| 4 | Statistiky a další výzvy | Základní výzvy už počítá `GarageProgress` idempotentně z uložených spotů; další rozšířit stejným způsobem |
| 5 | Export/import a volitelný sync | Nejprve verzovaný přenosný archiv; pak řešit konflikty, tombstones, přenos médií a kompatibilitu CloudKit |
| 6 | Video, případně 3D experiment | Video → omezený výběr snímků se zdrojovým časem; 3D pouze samostatný experiment s realistickými nároky |

Vícepohledová identifikace nesmí prostě průměrovat nekalibrovaná skóre. Nejprve ověřit, že snímky patří stejnému spotu, a navrhnout vyhodnocení fúze. 3D z jedné fotky nemůže věrně doložit neviděné části auta; případný generovaný výsledek označit jako ilustraci.

## 11. Kvalita a zdroje

Produktovou kvalitu posuzovat podle dokončitelnosti importu, možnosti opravy, integrity fotografií a použitelnosti s asistivními technologiemi. Rychlost a spotřebu paměti měřit na konkrétním zařízení; neuvádět neověřenou univerzální latenci.

Oficiální technické zdroje pro implementaci (ověřované 28. 10. 2026; konkrétní dostupnost API potvrdit v použitém SDK):

- [Apple Vision](https://developer.apple.com/documentation/vision) — rozdělení úloh a dostupnost nového Swift API od iOS 18.
- [Foreground instance masks](https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest) a [WWDC23: Lift subjects](https://developer.apple.com/videos/play/wwdc2023/10176/) — izolace popředí, nikoli katalogová identifikace vozů.
- [Core ML](https://developer.apple.com/documentation/coreml) — běh modelů na zařízení.
- [VersionedSchema](https://developer.apple.com/documentation/swiftdata/versionedschema) a [SchemaMigrationPlan](https://developer.apple.com/documentation/swiftdata/schemamigrationplan) — verzování persistence.
- [Apple HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) — nativní a přístupné rozhraní.

Volby schématu, minimálního OS a rozsahu výše jsou návrhová rozhodnutí SpotGearu, nikoli tvrzení o automatických schopnostech frameworků.
