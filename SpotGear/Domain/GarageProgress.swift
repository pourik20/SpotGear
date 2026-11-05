/// What one saved spot contributes to progress. Combines saved reward XP with the current card details.
struct SpotFacts: Equatable, Sendable {
    var make: String?
    var hasModel = false
    var hasDetail = false
    var hasNote = false
    var isFavorite = false

    var hasMake: Bool { make != nil }
    var isFullyIdentified: Bool { hasMake && hasModel && hasDetail }

    /// Share of the card's details the player has filled in, 0…1.
    var completion: Double {
        Double([hasMake, hasModel, hasDetail, hasNote].filter { $0 }.count) / 4
    }

    var xp: Int = SpotRarity.unknown.xp
}

enum GarageRank: CaseIterable, Sendable {
    case rookie
    case watcher
    case hunter
    case expert
    case master
    case legend

    init(level: Int) {
        self = switch level {
        case ..<3: .rookie
        case ..<5: .watcher
        case ..<8: .hunter
        case ..<12: .expert
        case ..<18: .master
        default: .legend
        }
    }
}

enum GarageQuest: CaseIterable, Identifiable, Sendable {
    case firstSpot
    case collector
    case threeMakes
    case tenMakes
    case detective
    case favorites

    var id: Self { self }

    var goal: Int {
        switch self {
        case .firstSpot: 1
        case .collector: 10
        case .threeMakes: 3
        case .tenMakes: 10
        case .detective: 5
        case .favorites: 3
        }
    }
}

/// Level, XP and quests computed idempotently from saved spots, so editing or deleting a spot
/// simply recalculates them and nothing can get out of sync with the collection.
struct GarageProgress: Equatable, Sendable {
    let spotCount: Int
    let makeCount: Int
    let fullyIdentifiedCount: Int
    let favoriteCount: Int
    let xp: Int
    let level: Int
    /// XP earned inside the current level.
    let xpIntoLevel: Int
    /// XP the current level takes in total.
    let xpForLevel: Int

    var rank: GarageRank { GarageRank(level: level) }
    var levelProgress: Double { Double(xpIntoLevel) / Double(xpForLevel) }

    init(spots: [SpotFacts]) {
        spotCount = spots.count
        // Compared ignoring case and diacritics, so "Škoda" and "skoda" count as one make.
        makeCount = Set(spots.compactMap(\.make).map { SearchText.fold($0) }).count
        fullyIdentifiedCount = spots.filter(\.isFullyIdentified).count
        favoriteCount = spots.filter(\.isFavorite).count
        xp = spots.reduce(0) { $0 + $1.xp }

        var level = 1
        var remaining = xp
        while remaining >= Self.xpNeeded(forLevel: level) {
            remaining -= Self.xpNeeded(forLevel: level)
            level += 1
        }
        self.level = level
        xpIntoLevel = remaining
        xpForLevel = Self.xpNeeded(forLevel: level)
    }

    /// XP needed to get from `level` to the next one.
    static func xpNeeded(forLevel level: Int) -> Int {
        100 + (level - 1) * 50
    }

    func progress(of quest: GarageQuest) -> Int {
        let value = switch quest {
        case .firstSpot, .collector: spotCount
        case .threeMakes, .tenMakes: makeCount
        case .detective: fullyIdentifiedCount
        case .favorites: favoriteCount
        }
        return min(value, quest.goal)
    }

    func isCompleted(_ quest: GarageQuest) -> Bool {
        progress(of: quest) >= quest.goal
    }

    var completedQuestCount: Int {
        GarageQuest.allCases.filter(isCompleted).count
    }
}
