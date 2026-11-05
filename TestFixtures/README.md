# Test fixtures

Zdroj: [`SpotGear/App/Debug/FixtureImageFactory.swift`](../SpotGear/App/Debug/FixtureImageFactory.swift) (kompiluje se pouze v DEBUG).

## Reálná fotografie

| Soubor | Účel | Původ / licence |
|---|---|---|
| [`SpotGear/tesla.jpeg`](../SpotGear/tesla.jpeg) (768 × 1024, portrét) | „Testovací fotografie“ v debug menu, test normalizace | Dodal autor projektu; **původ a licenci je třeba doplnit** |

Soubor je v Release buildu vyřazen (`EXCLUDED_SOURCE_FILE_NAMES`).

## Syntetické obrázky

Generují se v kódu, takže nevznikají otázky licence ani soukromí.

| Fixture | Účel |
|---|---|
| `threeCarsJPEG()` | Scéna se třemi jednoduchými siluetami aut; testy více aut a záloha, když `tesla.jpeg` chybí |
| `threeCarsJPEG(width:height:)` | Velký obrázek pro ověření downsamplingu |
| `quadrantsJPEG(exifOrientation: 6)` | Čtyři barevné kvadranty uložené otočené s EXIF orientací 6; ověření orientace a výřezu |
| `corruptedData()` | Poškozená hlavička JPEG; ověření chybové hlášky |

Fixtures obsahují EXIF datum pořízení a GPS záznam, aby šlo ověřit čtení data a odstranění metadat.

Dosud nepokryto (vyžaduje reálné fotografie s doloženou licencí nebo manuální ověření na zařízení): zhoršené světlo, překryv skutečných aut, neautomobilový objekt s reálnou segmentací.
