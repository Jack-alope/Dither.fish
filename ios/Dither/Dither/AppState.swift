import Foundation
import Combine

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    @Published var gear: [GearItem] = []
    @Published var bundles: [GearBundle] = []
    @Published var trips: [Trip] = []
    @Published var catalog: [CatalogItem] = []
    @Published var pendingCatalog: [CatalogItem] = []

    @Published var isAdmin: Bool = false
    @Published var username: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String?

    private let tokenKey = "dither_token"
    private let gearKey = "dither_gear"
    private let bundlesKey = "dither_bundles"
    private let tripsKey = "dither_trips"
    private let catalogKey = "dither_catalog"
    private let usernameKey = "dither_username"
    private let isAdminKey = "dither_isAdmin"

    var token: String? {
        get { UserDefaults.standard.string(forKey: tokenKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: tokenKey)
            APIService.shared.token = newValue
        }
    }

    init() {
        APIService.shared.token = token
        username = UserDefaults.standard.string(forKey: usernameKey) ?? ""
        isAdmin = UserDefaults.standard.bool(forKey: isAdminKey)
        loadCache()
        if token != nil {
            Task { await fetchAll() }
        }
    }

    // MARK: - Cache
    private func loadCache() {
        gear = loadFromCache(key: gearKey) ?? []
        bundles = loadFromCache(key: bundlesKey) ?? []
        trips = loadFromCache(key: tripsKey) ?? []
        catalog = loadFromCache(key: catalogKey) ?? []
    }

    private func loadFromCache<T: Decodable>(key: String) -> [T]? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([T].self, from: data)
    }

    private func saveToCache<T: Encodable>(_ items: [T], key: String) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - Fetch All
    func fetchAll() async {
        isLoading = true
        error = nil
        async let g: () = fetchGear()
        async let b: () = fetchBundles()
        async let t: () = fetchTrips()
        async let c: () = fetchCatalog()
        _ = await (g, b, t, c)
        isLoading = false
    }

    // MARK: - Auth
    func login(username: String, password: String) async throws {
        let resp = try await APIService.shared.login(username: username, password: password)
        token = resp.token
        self.username = resp.username
        self.isAdmin = resp.isAdmin
        UserDefaults.standard.set(resp.username, forKey: usernameKey)
        UserDefaults.standard.set(resp.isAdmin, forKey: isAdminKey)
        await fetchAll()
    }

    func register(username: String, password: String) async throws {
        let resp = try await APIService.shared.register(username: username, password: password)
        token = resp.token
        self.username = resp.username
        self.isAdmin = resp.isAdmin
        UserDefaults.standard.set(resp.username, forKey: usernameKey)
        UserDefaults.standard.set(resp.isAdmin, forKey: isAdminKey)
        await fetchAll()
    }

    func logout() {
        token = nil
        username = ""
        isAdmin = false
        gear = []
        bundles = []
        trips = []
        catalog = []
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: gearKey)
        UserDefaults.standard.removeObject(forKey: bundlesKey)
        UserDefaults.standard.removeObject(forKey: tripsKey)
        UserDefaults.standard.removeObject(forKey: catalogKey)
        UserDefaults.standard.removeObject(forKey: usernameKey)
        UserDefaults.standard.removeObject(forKey: isAdminKey)
    }

    // MARK: - Gear
    func fetchGear() async {
        do {
            let items = try await APIService.shared.fetchGear()
            gear = items
            saveToCache(items, key: gearKey)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addGear(name: String, brand: String, category: String, weight: Double?, qty: Int, notes: String) async throws {
        let req = GearItemRequest(name: name, brand: brand, category: category, weight: weight, qty: qty, notes: notes)
        let item = try await APIService.shared.createGear(req)
        gear.append(item)
        saveToCache(gear, key: gearKey)
    }

    func updateGear(id: String, name: String, brand: String, category: String, weight: Double?, qty: Int, notes: String) async throws {
        let req = GearItemRequest(name: name, brand: brand, category: category, weight: weight, qty: qty, notes: notes)
        let updated = try await APIService.shared.updateGear(id: id, item: req)
        if let idx = gear.firstIndex(where: { $0.id == id }) {
            gear[idx] = updated
        }
        saveToCache(gear, key: gearKey)
    }

    func deleteGear(id: String) async throws {
        try await APIService.shared.deleteGear(id: id)
        gear.removeAll { $0.id == id }
        saveToCache(gear, key: gearKey)
    }

    // If forTripId is provided and that trip is archived, resolves from the frozen snapshot.
    func gearById(_ id: String, forTripId: String? = nil) -> GearItem? {
        if let tripId = forTripId,
           let trip = trips.first(where: { $0.id == tripId }),
           trip.archived,
           let frozen = trip.frozenGear {
            return frozen.first { $0.id == id } ?? gear.first { $0.id == id }
        }
        return gear.first { $0.id == id }
    }

    func bundleById(_ id: String, forTripId: String? = nil) -> GearBundle? {
        if let tripId = forTripId,
           let trip = trips.first(where: { $0.id == tripId }),
           trip.archived,
           let frozen = trip.frozenBundles {
            return frozen.first { $0.id == id } ?? bundles.first { $0.id == id }
        }
        return bundles.first { $0.id == id }
    }

    // MARK: - Archive / Unarchive
    func archiveTrip(id: String) async throws {
        guard var trip = trips.first(where: { $0.id == id }) else { return }
        // Collect all gear IDs directly referenced in pack items
        let packGearIds = Set(trip.packs.flatMap { $0.items.map { $0.gearId } })
        // Collect all bundle IDs referenced in pack bundle refs
        let bundleIds = Set(trip.packs.flatMap { $0.bundleRefs.map { $0.bundleId } })
        let referencedBundles = bundles.filter { bundleIds.contains($0.id) }
        // Gear inside those bundles
        let bundleGearIds = Set(referencedBundles.flatMap { $0.items.map { $0.gearId } })
        let allGearIds = packGearIds.union(bundleGearIds)

        trip.archived     = true
        trip.frozenGear    = gear.filter { allGearIds.contains($0.id) }
        trip.frozenBundles = referencedBundles
        try await updateTrip(trip)
    }

    func unarchiveTrip(id: String) async throws {
        guard var trip = trips.first(where: { $0.id == id }) else { return }
        trip.archived      = false
        trip.frozenGear    = nil
        trip.frozenBundles = nil
        try await updateTrip(trip)
    }

    // MARK: - Bundles
    func fetchBundles() async {
        do {
            let items = try await APIService.shared.fetchBundles()
            bundles = items
            saveToCache(items, key: bundlesKey)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addBundle(name: String) async throws {
        let bundle = try await APIService.shared.createBundle(name: name)
        bundles.append(bundle)
        saveToCache(bundles, key: bundlesKey)
    }

    func updateBundle(id: String, name: String, items: [BundleItem]) async throws {
        let req = BundleRequest(name: name, items: items)
        let updated = try await APIService.shared.updateBundle(id: id, req: req)
        if let idx = bundles.firstIndex(where: { $0.id == id }) {
            bundles[idx] = updated
        }
        saveToCache(bundles, key: bundlesKey)
    }

    func deleteBundle(id: String) async throws {
        try await APIService.shared.deleteBundle(id: id)
        bundles.removeAll { $0.id == id }
        saveToCache(bundles, key: bundlesKey)
    }

    // MARK: - Trips
    func fetchTrips() async {
        do {
            let items = try await APIService.shared.fetchTrips()
            trips = items
            saveToCache(items, key: tripsKey)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addTrip(name: String, destination: String, startDate: String, endDate: String, notes: String) async throws {
        let req = TripRequest(name: name, destination: destination, startDate: startDate, endDate: endDate, notes: notes, packs: [], archived: false, frozenGear: nil, frozenBundles: nil)
        let trip = try await APIService.shared.createTrip(req)
        trips.append(trip)
        saveToCache(trips, key: tripsKey)
    }

    func updateTrip(_ trip: Trip) async throws {
        // Optimistically update local state immediately so the UI responds at once
        if let idx = trips.firstIndex(where: { $0.id == trip.id }) {
            trips[idx] = trip
        }
        let req = TripRequest(name: trip.name, destination: trip.destination, startDate: trip.startDate, endDate: trip.endDate, notes: trip.notes, packs: trip.packs, archived: trip.archived, frozenGear: trip.frozenGear, frozenBundles: trip.frozenBundles)
        var updated = try await APIService.shared.updateTrip(id: trip.id, req: req)
        // The server may not yet have archived/frozenGear/frozenBundles in its schema.
        // If it stripped them, preserve our local values so the UI stays correct.
        if trip.archived && !updated.archived {
            updated.archived      = trip.archived
            updated.frozenGear    = trip.frozenGear
            updated.frozenBundles = trip.frozenBundles
        }
        if let idx = trips.firstIndex(where: { $0.id == trip.id }) {
            trips[idx] = updated
        }
        saveToCache(trips, key: tripsKey)
    }

    func updatePack(tripId: String, packIndex: Int, pack: Pack) async throws {
        guard var trip = trips.first(where: { $0.id == tripId }) else { return }
        guard packIndex < trip.packs.count else { return }
        trip.packs[packIndex] = pack
        try await updateTrip(trip)
    }

    func addPackToTrip(tripId: String) async throws {
        guard var trip = trips.first(where: { $0.id == tripId }) else { return }
        let packNum = trip.packs.count + 1
        trip.packs.append(Pack(name: "Pack \(packNum)"))
        try await updateTrip(trip)
    }

    func renamePack(tripId: String, packIndex: Int, name: String) async throws {
        guard var trip = trips.first(where: { $0.id == tripId }),
              packIndex < trip.packs.count else { return }
        trip.packs[packIndex].name = name
        try await updateTrip(trip)
    }

    func deletePack(tripId: String, packIndex: Int) async throws {
        guard var trip = trips.first(where: { $0.id == tripId }),
              packIndex < trip.packs.count else { return }
        trip.packs.remove(at: packIndex)
        try await updateTrip(trip)
    }

    func deleteTrip(id: String) async throws {
        try await APIService.shared.deleteTrip(id: id)
        trips.removeAll { $0.id == id }
        saveToCache(trips, key: tripsKey)
    }

    // MARK: - Catalog
    func fetchCatalog() async {
        do {
            let items = try await APIService.shared.fetchCatalog()
            catalog = items
            saveToCache(items, key: catalogKey)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func suggestItem(name: String, brand: String, category: String, weight: Double?, notes: String) async throws {
        let req = CatalogSuggestRequest(name: name, brand: brand, category: category, weight: weight, notes: notes)
        try await APIService.shared.suggestCatalogItem(req)
    }

    func loadPending() async {
        guard isAdmin else { return }
        do {
            pendingCatalog = try await APIService.shared.fetchPendingCatalog()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func approveItem(id: String) async throws {
        try await APIService.shared.approveCatalogItem(id: id)
        pendingCatalog.removeAll { $0.id == id }
        await fetchCatalog()
    }

    func rejectItem(id: String) async throws {
        try await APIService.shared.deleteCatalogItem(id: id)
        pendingCatalog.removeAll { $0.id == id }
    }

    func editCatalogItem(id: String, name: String, brand: String, category: String, weight: Double?, notes: String) async throws {
        let req = CatalogEditRequest(name: name, brand: brand, category: category, weight: weight, notes: notes)
        let updated = try await APIService.shared.editCatalogItem(id: id, req: req)
        if let idx = pendingCatalog.firstIndex(where: { $0.id == id }) {
            pendingCatalog[idx] = updated
        }
        if let idx = catalog.firstIndex(where: { $0.id == id }) {
            catalog[idx] = updated
        }
    }
}
