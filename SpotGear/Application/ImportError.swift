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
        case .unreadableImage: String(localized: "Unable to Open File")
        case .insufficientSpace: String(localized: "Not Enough Storage")
        case .photoUnavailable: String(localized: "Photo Unavailable")
        case .saveFailed: String(localized: "Unable to Save")
        }
    }

    var message: String {
        switch self {
        case .unreadableImage:
            String(localized: "The selected file couldn't be read as a photo. It may be damaged. Please choose another photo.")
        case .insufficientSpace:
            String(localized: "There isn't enough free storage. Free up some space and try again. Your saved collection is unchanged.")
        case .photoUnavailable:
            String(localized: "Couldn't load the photo. If it's stored only in iCloud, connect to the internet or choose another photo.")
        case .saveFailed:
            String(localized: "Couldn't save the cars. Your collection is unchanged. Please try again.")
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
