# ADR 0004 — Automatická detekce aut a lokální katalog cen

Datum: 2026-10-30 · Stav: přijato

## Kontext

Ruční označování auta rámečkem je špatné UX; aplikace má auta na fotce najít sama, i více najednou. Po potvrzení má ukázat přibližnou cenu a základní údaje. Obojí mění dřívější non-goals (`MVP.md`, `PROJECT.md`). Vlastní model nemáme a iOS 27 SDK nemá obecný detektor objektů (Vision detekuje jen lidi a zvířata).

Měření na macOS 27 se stejným systémovým modelem (8 aut, `SystemLanguageModel.default`, greedy):

| Dotaz | Výsledek |
|---|---|
| Rámečky aut z fotky | Nepoužitelné (např. `top` větší než `bottom`) |
| Česky: cena a údaje | 150–300 tis. Kč i pro Ferrari F40 a Bugatti Chiron; Škoda Favorit „1998–2008, diesel“; rozbitá čeština |
| Anglicky, s kalibračními příklady | Bugatti Chiron 150–250 tis. €; Favorit dostal údaje Octavie; stejné auto se mezi formulacemi liší několikanásobně |
| Cenová kategorie (`budget` … `collectible`) | 8 z 8 věrohodných; malý vzorek |

## Rozhodnutí

1. **Detekce:** `VisionVehicleDetector` skládá systémové požadavky: instance popředí navrhnou rámečky, `VNClassifyImageRequest` ponechá ty se štítkem auta. Když popředí nic nenajde, zkusí se objektová saliency. Bez třetích stran a bez modelu ke stažení.
2. **Tok:** `loading → detecting → reviewing`. Nalezená auta se rovnou zpracují a čekají v souhrnu na potvrzení. Ruční výběr (`selecting`) zůstává jen jako fallback: nenašlo se nic, detektor není dostupný, nebo chce uživatel přidat auto přes „Upravit výběr“.
3. **Předvyplnění:** nejlepší návrh se předvyplní do formuláře. Potvrzení dál provádí uživatel; odmítnutí nebo změna výřezu předvyplněný text odstraní.
4. **Ceny a údaje nepocházejí z jazykového modelu.** Zdrojem je `Resources/VehicleCatalog.json` s orientačními rozpětími pro 131 generací běžných i významných aut. Vyhledávání je deterministické, offline a nevyžaduje změnu schématu, protože se údaje dopočítají z potvrzené identity a nic se neukládá.
5. **Auta mimo katalog** dostanou nanejvýš hrubou cenovou kategorii od systémového modelu, označenou jako jeho odhad. Model se na konkrétní cenu nikdy neptá.

## Důsledky

- Nalezne hlavně výrazná auta v popředí. Zakrytá auta v pozadí detektor často vynechá (bílé auto za plotem na testovací fotce) a překrývající se auta mohou splynout v jeden rámeček; proto zůstává ruční přidání.
- Detekce potřebuje Vision na skutečném zařízení. V simulátoru je `unavailable` a aplikace přejde na ruční výběr.
- Prahy jsou změřené na malém vzorku (`tesla.jpeg` a její kompozice). Kvalitu je třeba vyhodnotit na reálných fotkách více aut.
- Katalog sestavil vývoj odhadem, ne z aktuálních inzerátů, a časem zastarává. Rozpětí jsou proto široká, UI uvádí stav dat a že jde o typ auta, ne o konkrétní kus. Před vydáním je potřeba ceny porovnat s trhem a katalog pravidelně aktualizovat.
- Přesnou tržní cenu by dala jen síťová data, což je mimo local-first a vyžadovalo by samostatné rozhodnutí.
- Schéma V1 se nemění.
