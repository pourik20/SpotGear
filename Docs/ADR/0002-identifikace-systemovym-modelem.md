# ADR 0002 — Návrhy identifikace systémovým modelem v zařízení

Datum: 2026-10-28 · Stav: přijato

## Kontext

MVP počítá s volitelným Core ML klasifikátorem, který ale nemáme (licence, trénovací data). iOS 27 SDK přidal do frameworku Foundation Models obrazový vstup (`Attachment` s `CGImage`, schopnost `LanguageModelCapabilities.Capability.vision`). Systémový jazykový model běží v zařízení, je součástí OS a nevyžaduje API klíč, server ani stahování vah aplikací.

## Rozhodnutí

1. **Nový adaptér `SystemModelVehicleIdentifier`** (`Infrastructure/FoundationModels`) implementuje stávající port `VehicleIdentifier`. Používá výhradně `SystemLanguageModel.default`, nikdy `PrivateCloudComputeLanguageModel` ani síť — local-first zůstává zachováno.
2. **Pořadí providerů:** dodaný a validní Core ML klasifikátor má přednost; jinak systémový model. UI testy a test host používají jen Core ML adaptér (bez modelu), aby byly deterministické.
3. **Strukturovaný výstup** přes `@Generable` (`showsCar` + nejvýše 3 návrhy značka/model/generace), greedy sampling. Rok se nikdy nežádá. Když na snímku není auto, výsledkem je prázdný seznam.
4. **Výstup modelu se považuje za nedůvěryhodný text:** `VehicleSuggestionRules` ořízne mezery, zahodí prázdné/zástupné hodnoty („unknown“, „n/a“…), generaci bez modelu, duplicity (bez ohledu na velikost písmen a diakritiku) a omezí počet na 3. Skóre se nevymýšlí — `VehicleCandidate.score` je nově volitelné; staré snapshoty se skóre se dál dekódují.
5. **Pravdivé stavy nedostupnosti:** iOS < 27 / model bez obrazového vstupu, nepodporované zařízení, vypnutá Apple Intelligence, model se připravuje. Každý má vlastní text a vždy nabízí ruční vyplnění. Odmítnutí modelem (guardrail/refusal) = „žádné návrhy“, ne chyba.
6. Pokus se ukládá do `IdentificationAttempt` jen při skutečné inferenci; `modelVersion` = verze OS (`ios-27.0`), protože systémový model nemá vlastní veřejnou verzi.

## Důsledky

- Na iOS 17–26 a zařízeních bez Apple Intelligence se chování nemění (ruční identifikace).
- Kvalita návrhů není změřená; model může chybovat i u běžných aut. UI to uvádí a návrh vždy jen předvyplní formulář — potvrzuje uživatel (beze změny pravidel MVP).
- Systémový model se může aktualizací OS změnit; uložené potvrzené identity se tím nemění.
- Schéma V1 se nemění (rozšířen jen enum důvodů a volitelné pole v Codable payloadu kandidátů).
