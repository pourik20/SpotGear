# SpotGear MVP — proveditelné zadání pro coding agenta

Verze 1.0 · 28. října 2026 · související vize: [PROJECT.md](PROJECT.md)

## 1. Cíl a závaznost

Postav nativní iOS aplikaci, ve které lze bez internetu vyfotit/importovat fotografii, označit na ní více aut, každé ručně identifikovat nebo ponechat neznámé a uložit jako samostatnou fotokartu. Kolekce přežije restart, umožňuje hledání, opravy, oblíbené a bezpečné mazání.

MVP musí být dokončitelné **bez externího modelu, API klíče, serveru a účtu**. Lokální Vision segmentace je reálná součást implementace s fallbackem. Konkrétní Core ML klasifikátor značek/modelů není dodán a jeho získání ani trénování není podmínkou dokončení. Implementuj integrační adaptér a pravdivý stav nedostupnosti; nevydávej ruční režim za automatické rozpoznávání.

Automatická detekce aut a lokální katalog cen rozšiřují původní rozsah, viz [ADR 0004](../Docs/ADR/0004-detekce-aut-a-katalog-cen.md).

Tento dokument je závazný pro rozsah. PROJECT.md definuje význam pojmů a budoucí směr. Pokud implementace odhalí konflikt, zaznamenej rozhodnutí do krátkého ADR a zachovej offline funkčnost, data a možnost ruční opravy.

## 2. Technický základ

- iPhone, iOS 17+, SwiftUI, SwiftData, Vision, Core ML, PhotosUI, ImageIO/Core Graphics. Adaptivní layout; samostatné iPad UX není součástí MVP.
- Aktuální stabilní Xcode, konkrétní verzi a deployment target zapsat do README. Použít API dostupná na iOS 17; novější funkce pouze s availability fallbackem.
- Jeden app target, unit a UI test target. Žádné povinné třetí závislosti. Pro kameru stačí systémový capture wrapper; vlastní AVFoundation kamera není nutná.
- Veškeré řetězce ve String Catalog, výchozí čeština. Assety a fixtures musí mít doložený původ/licenci.
- Vytvořit otevřitelný Xcode projekt se sdíleným schématem. Build pro simulator nesmí vyžadovat developer účet ani model ke stažení.

## 3. Povinný rozsah

### A. Kolekce

`NavigationStack`, adaptivní mřížka fotokaret, tlačítko přidání, hledání podle značky/modelu a filtr oblíbených. Řazení od nejnovějšího spotu. Vyhledávání ignoruje velikost písmen a diakritiku. Prázdná kolekce vysvětluje první krok a nabízí přidání fotografie.

Karta: obraz 4:3, název nebo „Neznámé auto“, datum vytvoření/pozorování podle dostupnosti, oblíbenost. Žádné procento „jistoty“ ani nepodložená rarita. Na velkém Dynamic Type použít jeden sloupec a rostoucí textové části.

### B. Vstup

Nabídnout fotoaparát a PhotosPicker s jedním snímkem. Kamera žádá oprávnění až při použití a má popis účelu v Info.plist. Když není dostupná nebo je zamítnuta, zachovat import z knihovny. Simulator nabízí import a testovací data jen v debug/test režimu.

Po výběru načíst lokální kopii, ověřit dekódování, normalizovat orientaci a odstranit nepotřebná metadata. Pro pracovní obraz použít downsampling; nikdy zbytečně nedržet všechny plné bitmapy současně. Chyba poškozeného souboru, nedostatek místa a iCloud-only fotografie bez internetu mají konkrétní vysvětlení a návrat k výběru.

### C. Výběr více aut

Zobrazit orientovanou fotografii s oblastmi. Akce „Přidat auto“ založí přednastavený obdélník, který lze posunout a změnit jeho velikost. Každá oblast má UUID a číslo. Seznam pod fotografií umožní vybrat/odebrat oblast a přejít na její potvrzení. Výběr nesmí záviset na úspěchu AI.

V MVP podporuj 1–10 oblastí v jedné fotografii; limit je ochrana UI a paměti, nikoli tvrzení o počtu aut. Překryv oblastí je dovolený. Nic automaticky neslučuj. Výchozí žádná oblast; uložit nelze bez alespoň jedné potvrzené oblasti.

Zajisti alternativu ke gestům pro VoiceOver: pojmenovaná oblast, tlačítka nebo nastavitelné prvky pro posun a velikost, čitelná pozice/rozměr a akce přidat/odebrat. Geometrie musí respektovat letterboxing/aspect-fit a EXIF orientaci.

### D. Identifikace a potvrzení

Pro každé auto zobraz výřez a formulář: značka, model, volitelná generace a rok, nebo „Nevím“. Text trimovat, nepřijímat model bez značky; prázdná značka znamená neznámé auto a vyčistí závislá pole. Rok je volitelný čtyřciferný údaj; při nevalidním vstupu vysvětlit chybu, nedoplňovat rok AI odhadem.

Pokud existuje kompatibilní zabudovaný klasifikátor, nabídni nejvýše tři návrhy a „Žádný z návrhů“. Výběr předvyplní formulář, ale finální potvrzení provede uživatel. Bez modelu zobraz „Automatická identifikace není v této verzi dostupná. Údaje můžete doplnit ručně.“ Změna výřezu zneplatní návrhy a stav potvrzení dané oblasti; ruční text lze zachovat jako rozepsaný.

Uživatel smí potvrdit neznámé auto. Každá oblast v závěrečném souhrnu musí být potvrzena nebo odstraněna. Uložení nevytváří spoty pro nevybrané objekty.

### E. Fotokarta

Výchozí spolehlivá karta používá obyčejný fotografický výřez. Pro výřez nabídni lokální segmentaci přes `VNGenerateForegroundInstanceMaskRequest`. Výsledek ber jako návrh: pokud existuje jedna použitelná instance, vytvoř alfa výřez a ukaž přepnutí „Výřez / Bez pozadí“. Při více nejednoznačných instancích, prázdné masce, chybě nebo nepodpoře ponech fotografický výřez. V MVP neimplementuj pokročilý editor masky.

Pozadí cutoutu je neutrální sémantická plocha nebo jemný gradient přizpůsobený light/dark režimu. Zachovej proporce auta, nevyplňuj chybějící části generativní AI. Uživatel vidí před uložením náhled a může vždy zvolit obyčejný výřez.

### F. Uložení, detail a nastavení

Souhrn → explicitní „Uložit N aut“ → jedna dávka do databáze. Uloží se N spotů, N vazeb SpotPhoto a jeden sdílený PhotoAsset. Opakované stisknutí během ukládání nesmí vytvořit duplicity. Po úspěchu zobraz kolekci.

Detail: fotokarta, původní normalizovaná fotografie, identifikace a její uživatelské potvrzení, datum, poznámka, oblíbené. Umožni změnu identity/poznámky, přepnutí vzhledu karty a smazání spotu s potvrzením. Editace výřezu již uloženého spotu není nutná v MVP. Odstranění jednoho spotu nesmí poškodit jiná auta ze stejného snímku.

Nastavení: stručné vysvětlení offline režimu, stavu identifikačního modelu, lokálních dat a systémové zálohy; akce „Smazat celou sbírku“ s jasným potvrzením. Import rozpracovaný při ukončení aplikace není nutné obnovit, ale nesmí poškodit uloženou sbírku.

## 4. Explicitní non-goals

Neimplementuj 3D, generované pohledy, video, více vstupních fotografií v jednom importu, trénování modelu, kompletní katalog, polohu/mapy, SPZ/OCR, synchronizaci, export/import archivu, účet, backend, analytiku, placené API, výzvy ani sociální funkce. Nepřidávej nákup modelu, stahování vah při startu ani cloudový fallback.

## 5. Architektura a kontrakty

Dodrž strukturu:

```text
SpotGear/
  App/
  Domain/
  Application/
  Features/{Collection,Capture,ImportReview,SpotDetail,Settings}/
  Infrastructure/{Persistence,Media,Vision,CoreML}/
  DesignSystem/
  Resources/
SpotGearTests/
SpotGearUITests/
TestFixtures/
Docs/
```

SwiftUI views skládají UI, neprovádějí inferenci ani zápis souborů. `@MainActor` stavový model importu koordinuje služby přes application vrstvu. Doménové hodnotové typy neimportují SwiftUI/Vision/SwiftData. Závislosti skládej v App; nepoužívej globální service locator.

Minimální rozhraní mají vyjadřovat tyto kontrakty; přesné Swift signatury přizpůsob bezpečné concurrency:

| Rozhraní | Vstup → výstup a odpovědnost |
|---|---|
| `MediaStore` | Import lokálních dat → staged asset; commit/cleanup; čtení a bezpečné mazání relativních cest |
| `VehicleIdentifier` | Výřez + revision → `available(candidates)` / `unavailable(reason)` / typovaná chyba |
| `ForegroundSegmenter` | Výřez → mask/cutout nebo `notUsable(reason)`; zrušení není chyba pro uživatele |
| `SpotRepository` | Uložení celé dávky, čtení, editace a mazání; explicitní rollback a vlastnictví ModelContext |

Renderer a geometrie mohou být konkrétní čisté typy; nevytvářej protokoly bez důvodu. Core ML adaptér načítá volitelný model a manifest z bundle, validuje vstup/výstup a mapování labelů. Pokud model chybí, vrací nedostupnost. Pro nespecifikované modelové formáty neslibuj univerzální parser: podporovaný kontrakt je obrazový klasifikátor s label→score výstupem a verzovanou mapou labelů. Chybný manifest vede k fallbacku, nikoli pádu. Detektor není tento klasifikátor.

### Stav importu

`idle → loading → detecting → reviewing → saving → completed`; `selecting` následuje po `detecting`, když se auto nenašlo, a je dostupné z `reviewing` pro ruční změny.

V `reviewing` má každá oblast samostatný stav: `pending / processing / needsConfirmation / confirmed`. Segmentace může selhat nezávisle na identifikaci. Návrat k výběru je dovolen před uložením. Cancel zruší rozpracování a staging; z obrazovky ukládání neumožni druhý commit. Chyba uložení vrátí uživatele k souhrnu s možností opakování.

Každá změna oblasti zvýší revision. Výsledky workeru aplikuj pouze při shodě import ID, region ID a revision. Zrušený nebo starší výsledek nesmí přepsat novější volbu. Inference/dekódování mimo hlavní executor; nejvýše jedna náročná obrazová operace současně. SwiftData objekty nesdílej přes hranice actorů; předávej DTO/UUID.

## 6. Persistence V1 a konzistence

Implementuj `VersionedSchema` V1 a `SchemaMigrationPlan` od začátku. Entitní kontrakt:

- `PhotoAsset`: UUID, createdAt, capturedAt?, relativePath, width, height, contentHash?.
- `Spot`: UUID, createdAt, updatedAt, observedAt?, note, isFavorite, identityStatus, make?, model?, generation?, year?, identitySource?, confirmedAt?.
- `SpotPhoto`: UUID, spot, photoAsset, order, isPrimary, cropX/Y/Width/Height, revision, cardStyle, renderVersion, cutoutPath?, thumbnailPath?.
- `IdentificationAttempt`: UUID, spot, createdAt, inputRevision, providerID, modelVersion?, labelMapVersion?, outcome, candidatesData (verzovaný Codable snapshot).

Spot vlastní své vazby a pokusy. PhotoAsset je sdílený. Jeden spot má v MVP přesně jednu primární vazbu, vztah je od začátku 1:N. `unknown` a `userConfirmed` jsou jediné uložené identity stavy; návrhy nejsou potvrzenou identitou. `manual` / `modelSuggestion` označuje původ potvrzeného údaje. U neznámého auta jsou identifikační údaje a confirmedAt prázdné; potvrzení kroku importu se drží odděleně v draftu.

Doménový crop je v rozsahu 0…1 s počátkem vlevo nahoře, vůči orientovanému zdroji. Ověř bounds, nenulovou plochu a převody k Vision. Neukládej absolutní sandbox cesty ani plné bitmapy do SwiftData.

### Ukládací protokol

1. Vytvoř unikátní import ID a staging adresář. Připrav normalizovaný zdroj a dostupné deriváty.
2. Atomicky přesuň připravené soubory do finálního umístění. Eviduj jen soubory vlastněné tímto importem.
3. Vlož celý batch do jednoho vlastněného ModelContext a explicitně `save`; nepoužívej autosave jako transakční mechanismus.
4. Při DB chybě rollback a cleanup nových souborů. Uživatel může dávku opakovat bez duplicit.
5. Po pádu při příštím startu porovnej reference a neaktivní importy. Osiřelé soubory uklízej až po ověření, že nejsou používané. Selhání cleanupu loguj bez citlivých dat a opakuj později.

Při mazání nejprve ulož odstranění metadat/vazeb, pak odstraň nereferencované soubory; pád může ponechat odpad, nesmí zneplatnit jiné spoty. Chybějící náhled regeneruj, chybějící zdroj zobraz jako nedostupný. Při otevření či migraci chybného store nikdy nepoužij automatický reset databáze.

## 7. UI a accessibility — implementační požadavky

- Systémové fonty a sémantické barvy, konzistentní rozestupy, jedna hlavní akce na krok, SF Symbols s textem nebo accessibility label.
- Světlý/tmavý režim, Dynamic Type včetně accessibility velikostí, minimálně 44 × 44 bodů pro aktivní plochy.
- VoiceOver pořadí odpovídá toku; karty mají smysluplné souhrnné popisky. Výběr a chyby se nekomunikují jen barvou.
- Reduce Motion respektovat; haptika pouze doplňková. Načítání neblokuje zrušení a nevymýšlí procenta.
- Přístupné ovládání regionu bez drag gesta je povinné, ne odložené rozšíření.
- Empty/loading/error/unavailable stavy vytvořit i v previews. Mockované AI výsledky označit a omezit na previews/testy.

## 8. Implementační pořadí

1. **Základ:** projekt, composition root, model V1, repository, souborové úložiště a malá sada legálních fixtures.
2. **Vertikální řez:** import jednoho snímku → jeden ruční výřez → neznámý spot → karta → restart → detail → mazání.
3. **Více aut:** seznam regionů, geometrie, individuální potvrzení a atomické uložení více spotů se sdíleným zdrojem.
4. **Lokální zpracování:** reálná Vision segmentace s fallbackem; Core ML adaptér a pravdivý missing-model stav. Nezdržuj hotovou základní cestu sháněním klasifikátoru.
5. **Dokončení produktu:** editace identity, hledání, oblíbené, nastavení, přístupnost a vizuální doladění.
6. **Ověření:** testy konzistence a chyb, skutečné zařízení, dokumentace a finální report známých omezení.

Po každém kroku zachovej build. DRY aplikuj na pravidla a skutečně sdílené komponenty, KISS na strukturu. SOLID použij k oddělení UI, koordinace a efektů; nezaváděj hlubokou hierarchii ani abstraktní základní view model.

## 9. Acceptance criteria

Všechny povinné body musí projít nebo být výslovně označeny jako neověřené s důvodem; neověřené není splněné.

| ID | Scénář | Očekávaný výsledek |
|---|---|---|
| AC01 | Čistý build bez modelu a API klíče | Projekt se sestaví; identifikace hlásí nedostupnost, žádné fiktivní návrhy |
| AC02 | Režim letadlo, lokální snímek, nové spuštění | Celý import až po restart a detail funguje offline |
| AC03 | Snímek obsahuje tři auta | Uživatel označí tři oblasti a uloží tři samostatné karty; DB obsahuje jeden zdroj |
| AC04 | AI nevrátí masku / není podporována | Import jde dokončit s fotografickým výřezem |
| AC05 | Uživatel nezná značku | Lze uložit „Neznámé auto“ a později údaje doplnit |
| AC06 | Testovací provider vrátí návrhy | Žádný se neuloží jako identita bez potvrzení; lze všechny odmítnout |
| AC07 | Změna regionu během zpracování | Starý výsledek se zahodí, nové potvrzení je vyžadováno |
| AC08 | Portrait, landscape a EXIF otočená fotografie | Oblasti, výřezy a karta zobrazují odpovídající část snímku bez otočení/zrcadlení navíc |
| AC09 | Cancel před uložením | Nevzniknou spoty; staging je odstraněn nebo bezpečně uklizen při dalším startu |
| AC10 | Dvojí stisk Uložit / opakování po chybě | Nevzniknou duplicitní spoty ani částečný batch |
| AC11 | Simulovaný nedostatek místa či chyba DB | Srozumitelná chyba, žádná falešná zpráva o uložení, existující kolekce je zachována |
| AC12 | Smazání jednoho ze tří spotů stejné fotky | Zbývající dva mají funkční zdroj i karty; poslední smazání uvolní zdroj |
| AC13 | Restart po uložení, editaci a oblíbenosti | Stav, pořadí a média zůstávají zachována |
| AC14 | VoiceOver a největší Dynamic Type | Import dvou aut lze dokončit bez drag gesta; akce jsou čitelné a dostupné |
| AC15 | Dark mode a Reduce Motion | Text i ovládání čitelné; UI nevyžaduje animaci k pochopení stavu |
| AC16 | Zamítnutá kamera / iCloud-only fotka offline | Aplikace nespadne; nabízí lokální alternativu a jasné vysvětlení |
| AC17 | Chybějící thumbnail / zdroj / chybný store | Náhled se obnoví, zdroj dostane chybný stav, store se nikdy automaticky nesmaže |
| AC18 | Hledání, úprava identity, filtr oblíbených | Výsledky odpovídají uloženým datům; úprava nepotřebuje internet |
| AC19 | Smazat celou sbírku, potvrdit a restartovat | Kolekce je prázdná a její média jsou odstraněna; zrušení potvrzení nic nemění |

## 10. Testovací plán a ověření

**Unit:** validace identity, crop bounds, převody souřadnic při aspect-fit a orientaci, invalidace revizí, stavové přechody, zrušení a odmítnutí zastaralého výsledku. Výstup AI testovat přes deterministický test double, nikoli očekáváním konkrétní značky z živého modelu.

**Integrační:** skutečný dočasný diskový SwiftData store, tři spoty/jeden asset, opětovné otevření store, delete rules, rollback při injektované chybě, obnova po přerušeném commit protokolu a úklid osiřelých souborů. In-memory store je doplněk, ne náhrada diskových testů.

**UI:** offline import bez klasifikátoru, potvrzení více regionů, neznámý spot, editace, hledání, oblíbené, mazání. Použít launch argumenty/test dependency injection pro fixtures a chyby; produkční build nesmí zpřístupnit testovací providery.

**Manuálně na zařízení:** fotoaparát a oprávnění, Vision segmentace, režim letadlo, VoiceOver, největší písmo, light/dark, Reduce Motion, velká fotografie a deset regionů. Změřit dobu importu a špičkovou paměť na uvedeném zařízení/OS; hlásit pozorované hodnoty bez univerzálního slibu. Náročná práce nesmí blokovat navigaci a cancel; v paměti nedržet deset plných kopií zdroje.

Test fixtures pokryjí více aut, překryv, zhoršené světlo, neautomobilový objekt, poškozený soubor a EXIF orientace. Neautomobilový snímek nesmí automaticky získat konkrétní automobilovou identitu. Manuální označení záměrně není validace skutečného obsahu.

V1 nemá předchozí produkční schéma. Ověř její uložení a opětovné otevření; nevytvářej fiktivní migraci jen pro test. Při první změně schématu přidej fixture starého store a test reálné migrace V1→V2 včetně médií a návrhů.

## 11. Rozšiřování bez přestavby

- Více fotografií přidá UI nad stávající `SpotPhoto`; neměň význam `Spot`.
- Katalog přidá volitelné stabilní ID vedle potvrzeného snapshotu. Ruční údaje musí zůstat použitelné bez katalogu.
- Nový klasifikátor vymění adaptér/manifest; staré potvrzené identity nepřepisuje. Model card uvede licenci, verzi, vstup, label map, pokrytí a naměřená omezení.
- Výzvy budou odvozené z uložených spotů a budou reagovat na editaci/mazání; nepřidávej je do MVP importní logiky.
- Synchronizace vyžaduje vlastní návrh konfliktů a mazání. Samotné použití SwiftData z MVP nedělá hotový synchronizační systém.
- Schéma, model, renderer a payload kandidátů verzuj samostatně. Vydané V1 neměň; data při migrační chybě zachovej.

## 12. Definition of Done a předání

Odevzdej zdrojový projekt, README s otevřením/buildem/testy, seznam podporovaných zařízení/OS podle skutečného ověření, krátké ADR, stav všech AC a známá omezení. Uveď přesně, zda je přítomen reálný klasifikátor, nebo běží ruční identifikace s lokální segmentací.

README vysvětlí, že není třeba API klíč, jak fungují fallbacky, kde jsou ukládána data, že odinstalace může odstranit sbírku a že lokální data mohou být zahrnuta do systémové zálohy. Přilož ukázky hlavních obrazovek z reálného běhu, nikoli jen previews.

Prohlašuj pouze testy, které jsi skutečně spustil. Pokud nemáš fyzické zařízení či potřebné oprávnění, dokonči ostatní práci a označ konkrétní manuální ověření jako zbývající. Nezaměňuj úspěšný simulator build za ověření kamery nebo kvality segmentace na telefonu.

Oficiální reference: [Vision](https://developer.apple.com/documentation/vision), [foreground mask](https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest), [Core ML](https://developer.apple.com/documentation/coreml), [SwiftData migrations](https://developer.apple.com/documentation/swiftdata/schemamigrationplan), [Apple accessibility HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility). Dostupnost konkrétních API ověř v použitém SDK.
