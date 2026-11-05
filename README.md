# SpotGear

An offline car-spotting app for iPhone. Turn the cars you discover into a personal collection of photo, studio, and pixel-art cards.

Built with SwiftUI, SwiftData, Vision, and on-device Apple Intelligence. No account, backend, API key, or external dependencies.

## Features

- **Collect from photos:** take a photo or import one from your library, then select up to 10 cars per image.
- **On-device identification:** review suggested makes and models, or enter the details manually.
- **Three card styles:** photo crops, studio cutouts with background removal, and locally rendered pixel art.
- **Your personal garage:** search, favorites, notes, editable vehicle details, XP, ranks, and quests.
- **Offline vehicle catalog:** production years, specifications, and rough used-price ranges in CZK.

Photos and collection data are stored and processed on your device. They may be included in system backups. Deleting the app also deletes its local collection.

## Getting Started

Requires **Xcode 27** with the **iOS 27 SDK**. The app targets **iOS 17 or later** on iPhone.

1. Open `SpotGear.xcodeproj` in Xcode.
2. Select the **SpotGear** scheme and an iPhone simulator or connected device.
3. Build and run with **⌘R**.

For the SwiftUI preview, open `SpotGear/App/RootView.swift`, enable **Editor → Canvas** (**⌥⌘↩**), and start **SpotGear – Collection**. The preview uses an in-memory database and separate temporary media. Debug builds include **Add Photo → Sample Photo** for trying the import flow.

## Testing

```sh
xcodebuild -project SpotGear.xcodeproj -scheme SpotGear \
  -destination 'generic/platform=iOS Simulator' \
  build-for-testing CODE_SIGNING_ALLOWED=NO
```

Run unit, integration, and UI tests with **⌘U** in Xcode using an available iPhone simulator. Tests cover import state, persistence, media processing, search, catalog lookup, and collection workflows.

If command-line builds use Command Line Tools instead of Xcode, prefix the command with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Limitations

- Automatic identification requires iOS 27 and an Apple Intelligence-capable device with the model available. Manual entry works on earlier versions.
- Car detection and background removal depend on Vision support and may be unavailable in the simulator. Verify these features and camera access on a physical device.
- Identification suggestions require your confirmation. Catalog prices are rough estimates, not live valuations or appraisals of the photographed car.
- Imports in progress are discarded when the app closes.

## Project Structure

`SpotGear/` separates the app composition, domain, application services, infrastructure, features, and shared UI. Tests live in `SpotGearTests/` and `SpotGearUITests/`.

The original product notes and architecture decisions are in [`SpotGear/PROJECT.md`](SpotGear/PROJECT.md), [`SpotGear/MVP.md`](SpotGear/MVP.md), and [`Docs/ADR/`](Docs/ADR/) (in Czech).

## Font Licenses

Pixelify Sans and Press Start 2P are distributed under the SIL Open Font License. License texts are included in [`SpotGear/Resources/Fonts/`](SpotGear/Resources/Fonts/).
