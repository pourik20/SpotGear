# ADR 0001 — Architektura MVP

Datum: 2026-10-28 · Stav: přijato

## Kontext

MVP musí fungovat offline, bez modelu a s atomickým ukládáním více aut z jedné fotografie (MVP.md §5–6).

## Rozhodnutí

1. **Vrstvy podle MVP.md §5.** Doménové typy jsou čisté hodnoty. Porty (`MediaStore`, `VehicleIdentifier`, `ForegroundSegmenter`, `SpotRepository`) jsou v `Application/Ports.swift`. Renderer, geometrie a `ImageWorker` jsou konkrétní typy bez protokolů.
2. **Composition root `AppServices`** se předává přes SwiftUI environment. Žádný globální service locator.
3. **Concurrency:** Swift 5 režim bez výchozí izolace na MainActor. `ImportSession`, repository a views jsou `@MainActor`; obrazová práce běží v actoru `ImageWorker`, soubory v actoru `FileMediaStore`. Přes hranice actorů jdou jen DTO (`RegionJob`, `SpotBatch`, UUID).
4. **Jeden zpracovávaný region současně.** `ImportSession` drží jedinou smyčku zpracování; změna výřezu zvýší revizi, zruší běžící úlohu a výsledek se použije jen při shodě import ID + region ID + revize.
5. **Ukládání:** náhledy → staging → atomický přesun souborů (`commit`) → jeden `ModelContext.save()`. Při chybě DB se soubory vrátí do stagingu (`rollback`) a import lze zopakovat. ID spotů = ID regionů, a `PhotoAsset.id` slouží jako klíč idempotence, takže opakování nevytvoří duplicity.
6. **Repository vlastní `mainContext` s vypnutým autosave**; čtení v UI přes `@Query`. Každý zápis je explicitní `save` s `rollback` při chybě.
7. **Úklid:** při startu se smaže staging neaktivních importů a soubory v `assets/` a `derived/`, na které DB neodkazuje (s výjimkou právě commitovaných). Mazání nejprve uloží DB, pak maže soubory.
8. **Normalizace zdroje:** ImageIO thumbnail s transformací (EXIF orientace), max. 4096 px, opětovné kódování JPEG bez metadat. Datum pořízení se čte z EXIF před odstraněním metadat.
9. **Debug-only testovací data:** `FakeVehicleIdentifier`, `FixtureImageFactory` a launch argumenty jsou za `#if DEBUG`.

## Důsledky

- Deployment target snížen ze šablonových 27.0 na 17.0 a target omezen na iPhone dle MVP.
- Rok výroby, generace a model nelze uložit bez značky; vyprázdnění značky vymaže závislá pole (řeší zdánlivý konflikt „model bez značky odmítnout“ × „prázdná značka znamená neznámé auto“).
- Výchozí vzhled karty je vždy fotografický výřez; výřez bez pozadí je volba uživatele.
