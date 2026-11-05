# ADR 0003: RPG vzhled a pixelové karty bez generativní AI

Stav: přijato · 30. října 2026

## Kontext

Původní vizuální směr byl střídmý a nativní. Vlastník produktu chce živější vzhled ve stylu Codédexu: pixelové písmo, progress bary, RPG prvky a auta jako pixel art. Zvažovali jsme generování obrázků lokálním modelem Apple (Image Playground).

Ověřeno v SDK iOS 27 (Xcode 27.0):

- Styly jsou jen `animation`, `illustration`, `sketch`, `emoji` a `externalProvider`; pixel art mezi nimi není.
- Programové `ImageCreator` je od iOS 27 označené jako deprecated. Zbývá sheet s ručním potvrzením uživatele pro každý obrázek.
- Vyžaduje zařízení s Apple Intelligence a model by vzhled auta domýšlel, což odporuje principu zachování skutečného vzhledu.

## Rozhodnutí

- Pixelová karta vzniká deterministickým zpracováním obrazu v `PixelArt`: zmenšení na mřížku 160 × 120, paleta median cut a obrys siluety. S výřezem z Vision stojí auto na scéně z `PixelScene`, bez něj se pixelizuje fotografický výřez.
- Karta se neukládá; kreslí se znovu z výřezu a v `CardImageLoader` se drží jen v paměti. `CardStyle.pixel` je nová hodnota existujícího textového pole, schéma V1 se nemění.
- Nové importy mají výchozí styl `pixel`. Styl jde v detailu kdykoli přepnout a původní fotografie zůstává beze změny.
- XP, úrovně a výzvy (`GarageProgress`) se počítají z uložených spotů, nic z toho se neukládá. Úprava nebo smazání auta je proto přepočítá.
- Aplikace používá jen tmavý vzhled. Pixelové fonty (Pixelify Sans, Press Start 2P, licence OFL) jsou přibalené a slouží pro nadpisy a krátké popisky; delší text zůstává v systémovém písmu.

## Důsledky

- Pixel art funguje offline na všech zařízeních bez nároků na Apple Intelligence.
- Kvalita závisí na výřezu z Vision, který simulátor neumí; tam se pixelizuje celý výřez fotografie.
- Styl není „nakreslený“: je věrný fotografii, ale nepřidává umělcovu stylizaci. Pokud by Apple přidal vhodný styl, lze ho doplnit jako další `CardStyle`.
- Světlý režim už není podporován.
