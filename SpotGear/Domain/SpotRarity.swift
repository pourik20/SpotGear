/// Game rarity based on the upper end of the catalog's CZK price range.
/// Unknown is deliberately separate from Common; model-generated price classes never award XP.
enum SpotRarity: String, CaseIterable, Sendable {
    case unknown, common, uncommon, rare, epic, legendary, mythic

    init(upperPriceCZK: Int?) {
        guard let price = upperPriceCZK, price > 0 else {
            self = .unknown
            return
        }
        self = switch price {
        case ..<250_000: .common
        case ..<750_000: .uncommon
        case ..<2_000_000: .rare
        case ..<5_000_000: .epic
        case ..<20_000_000: .legendary
        default: .mythic
        }
    }

    var xp: Int {
        switch self {
        case .unknown, .common: 25
        case .uncommon: 50
        case .rare: 100
        case .epic: 200
        case .legendary: 400
        case .mythic: 800
        }
    }
}
