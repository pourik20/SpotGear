import Foundation

/// User-facing import failures with a concrete explanation and a way back.
enum ImportError: Error, Equatable, Sendable {
    case unreadableImage
    case insufficientSpace
    case photoUnavailable
    case saveFailed

    enum Stage {
        case loading
        case saving
    }

    init(_ error: Error, stage: Stage) {
        if let importError = error as? ImportError {
            self = importError
        } else if let mediaError = error as? MediaError {
            switch mediaError {
            case .undecodable: self = .unreadableImage
            case .insufficientSpace: self = .insufficientSpace
            case .unsafePath, .missingStagedFile: self = stage == .loading ? .photoUnavailable : .saveFailed
            }
        } else if Self.isOutOfSpace(error) {
            self = .insufficientSpace
        } else {
            self = stage == .loading ? .photoUnavailable : .saveFailed
        }
    }

    var title: String {
        switch self {
        case .unreadableImage: String(localized: "Soubor nelze otevřít")
        case .insufficientSpace: String(localized: "Nedostatek místa")
        case .photoUnavailable: String(localized: "Fotografie není dostupná")
        case .saveFailed: String(localized: "Uložení se nezdařilo")
        }
    }

    var message: String {
        switch self {
        case .unreadableImage:
            String(localized: "Vybraný soubor se nepodařilo přečíst jako fotografii. Může být poškozený. Vyberte prosím jinou fotografii.")
        case .insufficientSpace:
            String(localized: "V zařízení není dost volného místa. Uvolněte místo a zkuste to znovu. Uložená sbírka zůstala beze změny.")
        case .photoUnavailable:
            String(localized: "Fotografii se nepodařilo načíst. Pokud je uložená jen na iCloudu a zařízení je offline, připojte se k internetu nebo vyberte jinou fotografii.")
        case .saveFailed:
            String(localized: "Auta se nepodařilo uložit. Sbírka zůstala beze změny a můžete to zkusit znovu.")
        }
    }

    private static func isOutOfSpace(_ error: Error) -> Bool {
        if let cocoa = error as? CocoaError, cocoa.code == .fileWriteOutOfSpace { return true }
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ENOSPC) { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error { return isOutOfSpace(underlying) }
        return false
    }
}
