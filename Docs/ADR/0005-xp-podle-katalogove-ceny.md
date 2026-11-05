# ADR 0005 — XP a RPG vzácnost podle katalogové ceny

Datum: 2026-11-05 · Stav: přijato

## Rozhodnutí

Horní hranice orientačního cenového rozpětí v CZK pro potvrzenou identitu určuje herní vzácnost a pevnou odměnu za každý uložený spot:

| Kategorie | Cena v Kč (dolní hranice včetně, horní bez) | XP | Barva |
|---|---|---:|---|
| Common | 0–250 000 | 25 | šedá |
| Uncommon | 250 000–750 000 | 50 | zelená |
| Rare | 750 000–2 000 000 | 100 | modrá |
| Epic | 2 000 000–5 000 000 | 200 | fialová |
| Legendary | 5 000 000–20 000 000 | 400 | oranžová |
| Mythic | 20 000 000 a více | 800 | červená |

Bez platné katalogové ceny je vzácnost neurčená a odměna 25 XP. Cenové kategorie od jazykového modelu se pro XP nepoužívají. Vzácnost je herní označení ceny, nikoli tvrzení o skutečném počtu vyrobených kusů.

Každý nový spot dostane plnou odměnu včetně opakovaných spotů stejného auta. Opakovaný zápis stejného importu nevytváří další spot ani XP. Poznámky, oblíbenost a další fotky již uloženého spotu XP nepřidávají.

Použije se stávající deterministické vyhledávání v katalogu: konkrétnější model, generace/alias nebo rok zužují výsledek. Pokud generace není známá, rozpětí zahrnuje všechny odpovídající generace a UI tuto nejistotu uvádí. Samostatné sportovní či limitované verze potřebují vlastní položku katalogu; nelze je odvozovat jen ze značky.

## Uložení a migrace

SchemaV2 přidává ke spotu cenu použitou pro odměnu, kategorii a počet XP. Schéma V1 zůstává neměnné, data se převedou lehkou migrací včetně vztahů k fotografiím. Při prvním otevření se stávající spoty jednorázově ohodnotí podle aktuálního katalogu. Jejich celkové XP a level se tím mohou změnit oproti původnímu systému odměn za vyplněné údaje.

Aktualizace cen nemění již určenou odměnu. Neurčené spoty se při dalším otevření aplikace dohodnotí, pokud již existuje katalogová cena. Skutečná změna potvrzené identity odměnu přepočítá; opětovné uložení stejné identity ji nemění. Všechny změny identity a odměny se ukládají v jedné transakci s rollbackem při chybě.

Celkové XP zůstávají součtem odměn uložených spotů. Smazání spotu odečte jeho příspěvek. Úrovně, hodnosti a výzvy zachovávají dosavadní pravidla.
