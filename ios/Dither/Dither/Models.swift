import Foundation

// MARK: - Auth
struct AuthResponse: Codable {
    let token: String
    let username: String
    let isAdmin: Bool
}

// MARK: - Gear
struct GearItem: Codable, Identifiable {
    let _id: String
    let name: String
    let brand: String
    let category: String
    let weight: Double?
    let qty: Int
    let notes: String

    var id: String { _id }
}

// MARK: - Bundle
struct GearBundle: Codable, Identifiable {
    let _id: String
    var name: String
    var items: [BundleItem]

    var id: String { _id }

    var totalWeight: Double {
        0 // calculated with gear lookup
    }
}

struct BundleItem: Codable {
    var gearId: String
    var qty: Int
}

// MARK: - Trips
struct Trip: Codable, Identifiable {
    let _id: String
    var name: String
    var destination: String
    var startDate: String
    var endDate: String
    var notes: String
    var packs: [Pack]
    var archived: Bool
    /// Snapshot of all referenced gear items taken at archive time.
    /// Non-nil only when archived == true.
    var frozenGear: [GearItem]?
    /// Snapshot of all referenced bundles taken at archive time.
    var frozenBundles: [GearBundle]?

    var id: String { _id }

    enum CodingKeys: String, CodingKey {
        case _id, name, destination, startDate, endDate, notes, packs, archived, frozenGear, frozenBundles
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id         = try c.decode(String.self, forKey: ._id)
        name        = try c.decode(String.self, forKey: .name)
        destination = (try? c.decodeIfPresent(String.self, forKey: .destination)) ?? ""
        startDate   = (try? c.decodeIfPresent(String.self, forKey: .startDate))   ?? ""
        endDate     = (try? c.decodeIfPresent(String.self, forKey: .endDate))     ?? ""
        notes       = (try? c.decodeIfPresent(String.self, forKey: .notes))       ?? ""
        packs       = (try? c.decodeIfPresent([Pack].self, forKey: .packs))       ?? []
        archived    = (try? c.decodeIfPresent(Bool.self, forKey: .archived))      ?? false
        frozenGear    = try? c.decodeIfPresent([GearItem].self, forKey: .frozenGear)
        frozenBundles = try? c.decodeIfPresent([GearBundle].self, forKey: .frozenBundles)
    }

    /// Direct initialiser — used when creating trips offline with a temp ID.
    init(_id: String, name: String, destination: String = "", startDate: String = "",
         endDate: String = "", notes: String = "", packs: [Pack] = [],
         archived: Bool = false, frozenGear: [GearItem]? = nil, frozenBundles: [GearBundle]? = nil) {
        self._id          = _id
        self.name         = name
        self.destination  = destination
        self.startDate    = startDate
        self.endDate      = endDate
        self.notes        = notes
        self.packs        = packs
        self.archived     = archived
        self.frozenGear   = frozenGear
        self.frozenBundles = frozenBundles
    }
}

struct Pack: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var cubes: [Cube]
    var items: [PackItem]
    var bundleRefs: [BundleRef]

    enum CodingKeys: String, CodingKey {
        case name, cubes, items, bundleRefs
    }

    init(name: String, cubes: [Cube] = [], items: [PackItem] = [], bundleRefs: [BundleRef] = []) {
        self.id = UUID()
        self.name = name
        self.cubes = cubes
        self.items = items
        self.bundleRefs = bundleRefs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        cubes = try container.decodeIfPresent([Cube].self, forKey: .cubes) ?? []
        items = try container.decodeIfPresent([PackItem].self, forKey: .items) ?? []
        bundleRefs = try container.decodeIfPresent([BundleRef].self, forKey: .bundleRefs) ?? []
        id = UUID()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(cubes, forKey: .cubes)
        try container.encode(items, forKey: .items)
        try container.encode(bundleRefs, forKey: .bundleRefs)
    }
}

struct Cube: Codable, Identifiable {
    var _id: String
    var name: String

    var id: String { _id }

    // Use this initialiser when creating a new cube locally.
    // A UUID string is fine as a temporary id; the server will assign
    // its own ObjectId and we re-fetch after saving.
    init(localName: String) {
        self._id  = UUID().uuidString
        self.name = localName
    }
}

enum ItemType: String, Codable, CaseIterable {
    case base
    case worn
    case consumable

    var label: String {
        switch self {
        case .base: return "Base"
        case .worn: return "Worn"
        case .consumable: return "Consumable"
        }
    }

    var icon: String {
        switch self {
        case .base: return "archivebox"
        case .worn: return "figure.walk"
        case .consumable: return "flame"
        }
    }
}

struct PackItem: Codable {
    var gearId: String
    var qty: Int
    var cubeId: String?
    var checked: Bool
    var type: ItemType
}

struct BundleRef: Codable {
    var bundleId: String
    var expanded: Bool
    var checkedItems: [String]
    var itemTypes: [BundleItemType]
    var cubeId: String?
}

struct BundleItemType: Codable {
    var gearId: String
    var type: ItemType
}

// MARK: - Catalog
struct CatalogVariant: Codable, Identifiable {
    let _id: String
    let name: String
    let weight: Double?
    var id: String { _id }
}

struct CatalogItem: Codable, Identifiable {
    let _id: String
    let name: String
    let brand: String
    let category: String
    let weight: Double?
    let notes: String
    let status: String
    let submittedBy: String?
    let variants: [CatalogVariant]

    var id: String { _id }

    enum CodingKeys: String, CodingKey {
        case _id, name, brand, category, weight, notes, status, submittedBy, variants
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id         = try c.decode(String.self, forKey: ._id)
        name        = try c.decode(String.self, forKey: .name)
        brand       = (try? c.decodeIfPresent(String.self, forKey: .brand))  ?? ""
        category    = (try? c.decodeIfPresent(String.self, forKey: .category)) ?? ""
        weight      = try? c.decodeIfPresent(Double.self, forKey: .weight)
        notes       = (try? c.decodeIfPresent(String.self, forKey: .notes))  ?? ""
        status      = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? ""
        submittedBy = try? c.decodeIfPresent(String.self, forKey: .submittedBy)
        variants    = (try? c.decodeIfPresent([CatalogVariant].self, forKey: .variants)) ?? []
    }
}

// MARK: - Generic API Result
struct OkResult: Codable {
    let ok: Bool
}

// MARK: - New item request bodies (for POST/PUT)
struct GearItemRequest: Codable {
    let name: String
    let brand: String
    let category: String
    let weight: Double?
    let qty: Int
    let notes: String
}

struct BundleRequest: Codable {
    let name: String
    let items: [BundleItem]
}

struct TripRequest: Codable {
    let name: String
    let destination: String
    let startDate: String
    let endDate: String
    let notes: String
    let packs: [Pack]
    let archived: Bool
    let frozenGear: [GearItem]?
    let frozenBundles: [GearBundle]?
}

struct CatalogSuggestRequest: Encodable {
    let name: String
    let brand: String
    let category: String
    let weight: Double?
    let notes: String
}

struct CatalogEditRequest: Encodable {
    let name: String
    let brand: String
    let category: String
    let weight: Double?
    let notes: String
}
