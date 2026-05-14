import Foundation
import Combine
import Network

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

    /// True when the device has a usable network path.
    @Published var isOnline: Bool = true
    /// Number of operations waiting to sync (drives the UI badge).
    @Published var pendingOpCount: Int = 0

    // MARK: - UserDefaults keys
    private let tokenKey       = "dither_token"
    private let gearKey        = "dither_gear"
    private let bundlesKey     = "dither_bundles"
    private let tripsKey       = "dither_trips"
    private let catalogKey     = "dither_catalog"
    private let usernameKey    = "dither_username"
    private let isAdminKey     = "dither_isAdmin"
    private let pendingOpsKey  = "dither_pendingOps"

    // MARK: - Offline queue (in memory; persisted to UserDefaults)
    private var pendingOps: [SyncOperation] = [] {
        didSet { pendingOpCount = pendingOps.count; savePendingOps() }
    }

    // MARK: - Network monitor (runs on a background queue)
    private let monitor  = NWPathMonitor()
    private let monitorQ = DispatchQueue(label: "dither.netmonitor")

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
        isAdmin  = UserDefaults.standard.bool(forKey: isAdminKey)
        pendingOps = loadPendingOps()
        loadCache()
        startNetworkMonitoring()
        if token != nil {
            Task { await fetchAll() }
        }
    }

    // MARK: - Network monitoring

    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let nowOnline = path.status == .satisfied
                let wasOffline = !self.isOnline
                self.isOnline = nowOnline
                if nowOnline && wasOffline && !self.pendingOps.isEmpty {
                    await self.syncPendingOps()
                }
            }
        }
        monitor.start(queue: monitorQ)
    }

    // MARK: - Queue persistence

    private func savePendingOps() {
        if let data = try? JSONEncoder().encode(pendingOps) {
            UserDefaults.standard.set(data, forKey: pendingOpsKey)
        }
    }

    private func loadPendingOps() -> [SyncOperation] {
        guard let data = UserDefaults.standard.data(forKey: pendingOpsKey) else { return [] }
        return (try? JSONDecoder().decode([SyncOperation].self, from: data)) ?? []
    }

    private func enqueue(_ op: SyncOperation) {
        pendingOps.append(op)
    }

    // MARK: - Sync pending operations

    func syncPendingOps() async {
        guard isOnline, !pendingOps.isEmpty else { return }

        var remaining = pendingOps  // snapshot
        var doneIds = Set<String>()

        for op in remaining {
            do {
                try await executeOp(op)
                doneIds.insert(op.id)
            } catch {
                if isNetworkError(error) {
                    break   // lost connectivity mid-drain — stop, will retry later
                } else {
                    // Server or logic error — skip this op so the queue doesn't stall
                    doneIds.insert(op.id)
                }
            }
        }

        pendingOps.removeAll { doneIds.contains($0.id) }

        // Re-fetch everything so local state reflects server truth
        if !doneIds.isEmpty {
            await fetchAll()
        }
    }

    /// Execute a single queued operation against the live API.
    private func executeOp(_ op: SyncOperation) async throws {
        switch op.type {

        // MARK: Gear
        case .addGear:
            let p = try decodePayload(AddGearPayload.self, from: op.payload)
            let item = try await APIService.shared.createGear(p.req)
            if let tempId = op.localId {
                replaceGearTempId(tempId, with: item)
                patchQueue(gearTempId: tempId, realId: item.id)
            }

        case .updateGear:
            let p = try decodePayload(UpdateGearPayload.self, from: op.payload)
            let updated = try await APIService.shared.updateGear(id: p.id, item: p.req)
            if let idx = gear.firstIndex(where: { $0.id == p.id }) { gear[idx] = updated }

        case .deleteGear:
            let p = try decodePayload(DeletePayload.self, from: op.payload)
            try await APIService.shared.deleteGear(id: p.id)

        // MARK: Bundles
        case .addBundle:
            let p = try decodePayload(AddBundlePayload.self, from: op.payload)
            let bundle = try await APIService.shared.createBundle(name: p.name)
            if let tempId = op.localId {
                replaceBundleTempId(tempId, with: bundle)
                patchQueue(bundleTempId: tempId, realId: bundle.id)
            }

        case .updateBundle:
            let p = try decodePayload(UpdateBundlePayload.self, from: op.payload)
            let updated = try await APIService.shared.updateBundle(id: p.id, req: p.req)
            if let idx = bundles.firstIndex(where: { $0.id == p.id }) { bundles[idx] = updated }

        case .deleteBundle:
            let p = try decodePayload(DeletePayload.self, from: op.payload)
            try await APIService.shared.deleteBundle(id: p.id)

        // MARK: Trips
        case .addTrip:
            let p = try decodePayload(AddTripPayload.self, from: op.payload)
            let trip = try await APIService.shared.createTrip(p.req)
            if let tempId = op.localId {
                replaceTripTempId(tempId, with: trip)
                patchQueue(tripTempId: tempId, realId: trip.id)
            }

        case .updateTrip:
            let p = try decodePayload(UpdateTripPayload.self, from: op.payload)
            // Use current local state if available (handles mid-queue ID remaps)
            if let local = trips.first(where: { $0.id == p.id }) {
                let req = TripRequest(name: local.name, destination: local.destination,
                                      startDate: local.startDate, endDate: local.endDate,
                                      notes: local.notes, packs: local.packs,
                                      archived: local.archived,
                                      frozenGear: local.frozenGear,
                                      frozenBundles: local.frozenBundles)
                var updated = try await APIService.shared.updateTrip(id: p.id, req: req)
                if local.archived && !updated.archived {
                    updated.archived      = local.archived
                    updated.frozenGear    = local.frozenGear
                    updated.frozenBundles = local.frozenBundles
                }
                if let idx = trips.firstIndex(where: { $0.id == p.id }) { trips[idx] = updated }
            } else {
                // Trip was deleted locally — skip
            }

        case .deleteTrip:
            let p = try decodePayload(DeletePayload.self, from: op.payload)
            try await APIService.shared.deleteTrip(id: p.id)
        }
    }

    // MARK: - Temp-ID remapping after an add syncs

    /// Replace a temp gear ID with the real server-assigned item throughout local state.
    private func replaceGearTempId(_ tempId: String, with real: GearItem) {
        if let idx = gear.firstIndex(where: { $0.id == tempId }) {
            gear[idx] = real
        }
        // Update pack items in all trips
        for ti in trips.indices {
            for pi in trips[ti].packs.indices {
                for ii in trips[ti].packs[pi].items.indices {
                    if trips[ti].packs[pi].items[ii].gearId == tempId {
                        trips[ti].packs[pi].items[ii].gearId = real.id
                    }
                }
                for ri in trips[ti].packs[pi].bundleRefs.indices {
                    trips[ti].packs[pi].bundleRefs[ri].checkedItems =
                        trips[ti].packs[pi].bundleRefs[ri].checkedItems.map {
                            $0 == tempId ? real.id : $0
                        }
                    for iti in trips[ti].packs[pi].bundleRefs[ri].itemTypes.indices {
                        if trips[ti].packs[pi].bundleRefs[ri].itemTypes[iti].gearId == tempId {
                            trips[ti].packs[pi].bundleRefs[ri].itemTypes[iti].gearId = real.id
                        }
                    }
                }
            }
        }
        // Update bundle items
        for bi in bundles.indices {
            bundles[bi].items = bundles[bi].items.map {
                $0.gearId == tempId ? BundleItem(gearId: real.id, qty: $0.qty) : $0
            }
        }
        saveToCache(gear,    key: gearKey)
        saveToCache(trips,   key: tripsKey)
        saveToCache(bundles, key: bundlesKey)
    }

    /// Replace a temp bundle ID with the real server-assigned bundle throughout local state.
    private func replaceBundleTempId(_ tempId: String, with real: GearBundle) {
        if let idx = bundles.firstIndex(where: { $0.id == tempId }) {
            bundles[idx] = real
        }
        for ti in trips.indices {
            for pi in trips[ti].packs.indices {
                for ri in trips[ti].packs[pi].bundleRefs.indices {
                    if trips[ti].packs[pi].bundleRefs[ri].bundleId == tempId {
                        trips[ti].packs[pi].bundleRefs[ri].bundleId = real.id
                    }
                }
            }
        }
        saveToCache(bundles, key: bundlesKey)
        saveToCache(trips,   key: tripsKey)
    }

    /// Replace a temp trip ID with the real server-assigned trip.
    private func replaceTripTempId(_ tempId: String, with real: Trip) {
        if let idx = trips.firstIndex(where: { $0.id == tempId }) {
            trips[idx] = real
        }
        saveToCache(trips, key: tripsKey)
    }

    // MARK: - Patch serialised queue payloads after temp-ID resolution

    /// After an add resolves, walk remaining queued ops and substitute the temp gear ID with the real one.
    private func patchQueue(gearTempId tempId: String, realId: String) {
        pendingOps = pendingOps.map { op in
            switch op.type {
            case .updateTrip:
                guard var p = try? decodePayload(UpdateTripPayload.self, from: op.payload) else { return op }
                var changed = false
                for pi in p.req.packs.indices {
                    for ii in p.req.packs[pi].items.indices where p.req.packs[pi].items[ii].gearId == tempId {
                        p.req.packs[pi].items[ii].gearId = realId
                        changed = true
                    }
                }
                if changed, let data = try? JSONEncoder().encode(p) { return op.withPayload(data) }
            case .updateBundle:
                guard var p = try? decodePayload(UpdateBundlePayload.self, from: op.payload) else { return op }
                let patched = p.req.items.map { BundleItem(gearId: $0.gearId == tempId ? realId : $0.gearId, qty: $0.qty) }
                if patched.map(\.gearId) != p.req.items.map(\.gearId) {
                    p = UpdateBundlePayload(id: p.id, req: BundleRequest(name: p.req.name, items: patched))
                    if let data = try? JSONEncoder().encode(p) { return op.withPayload(data) }
                }
            default:
                break
            }
            return op
        }
    }

    private func patchQueue(bundleTempId tempId: String, realId: String) {
        pendingOps = pendingOps.map { op in
            guard op.type == .updateTrip,
                  var p = try? decodePayload(UpdateTripPayload.self, from: op.payload) else { return op }
            var changed = false
            for pi in p.req.packs.indices {
                for ri in p.req.packs[pi].bundleRefs.indices where p.req.packs[pi].bundleRefs[ri].bundleId == tempId {
                    p.req.packs[pi].bundleRefs[ri].bundleId = realId
                    changed = true
                }
            }
            if changed, let data = try? JSONEncoder().encode(p) { return op.withPayload(data) }
            return op
        }
    }

    private func patchQueue(tripTempId tempId: String, realId: String) {
        // No other queued ops reference trip IDs — nothing to patch.
        _ = tempId; _ = realId
    }

    // MARK: - Network error detection

    private func isNetworkError(_ error: Error) -> Bool {
        if case APIError.networkError = error { return true }
        if let urlError = (error as? URLError) { return urlError.code != .cancelled }
        return false
    }

    // MARK: - Cache

    private func loadCache() {
        gear    = loadFromCache(key: gearKey)    ?? []
        bundles = loadFromCache(key: bundlesKey) ?? []
        trips   = loadFromCache(key: tripsKey)   ?? []
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
        self.isAdmin  = resp.isAdmin
        UserDefaults.standard.set(resp.username, forKey: usernameKey)
        UserDefaults.standard.set(resp.isAdmin,  forKey: isAdminKey)
        await fetchAll()
    }

    func register(username: String, password: String) async throws {
        let resp = try await APIService.shared.register(username: username, password: password)
        token = resp.token
        self.username = resp.username
        self.isAdmin  = resp.isAdmin
        UserDefaults.standard.set(resp.username, forKey: usernameKey)
        UserDefaults.standard.set(resp.isAdmin,  forKey: isAdminKey)
        await fetchAll()
    }

    func logout() {
        token    = nil
        username = ""
        isAdmin  = false
        gear    = []
        bundles = []
        trips   = []
        catalog = []
        pendingOps = []
        for key in [tokenKey, gearKey, bundlesKey, tripsKey, catalogKey, usernameKey, isAdminKey, pendingOpsKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
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

        // Create locally with a temp ID so the UI updates immediately
        let tempId = makeTempId()
        let local  = GearItem(_id: tempId, name: name, brand: brand, category: category, weight: weight, qty: qty, notes: notes)
        gear.append(local)
        saveToCache(gear, key: gearKey)

        guard isOnline else {
            enqueue(SyncOperation(type: .addGear, payload: encodePayload(AddGearPayload(req: req)), localId: tempId))
            return
        }

        do {
            let item = try await APIService.shared.createGear(req)
            replaceGearTempId(tempId, with: item)
        } catch {
            if isNetworkError(error) {
                enqueue(SyncOperation(type: .addGear, payload: encodePayload(AddGearPayload(req: req)), localId: tempId))
            } else {
                gear.removeAll { $0.id == tempId }
                saveToCache(gear, key: gearKey)
                throw error
            }
        }
    }

    func updateGear(id: String, name: String, brand: String, category: String, weight: Double?, qty: Int, notes: String) async throws {
        let req = GearItemRequest(name: name, brand: brand, category: category, weight: weight, qty: qty, notes: notes)

        // Optimistic local update
        if let idx = gear.firstIndex(where: { $0.id == id }) {
            gear[idx] = GearItem(_id: id, name: name, brand: brand, category: category, weight: weight, qty: qty, notes: notes)
        }
        saveToCache(gear, key: gearKey)

        guard isOnline else {
            enqueue(SyncOperation(type: .updateGear, payload: encodePayload(UpdateGearPayload(id: id, req: req))))
            return
        }

        do {
            let updated = try await APIService.shared.updateGear(id: id, item: req)
            if let idx = gear.firstIndex(where: { $0.id == id }) { gear[idx] = updated }
            saveToCache(gear, key: gearKey)
        } catch {
            if isNetworkError(error) {
                enqueue(SyncOperation(type: .updateGear, payload: encodePayload(UpdateGearPayload(id: id, req: req))))
            } else {
                throw error
            }
        }
    }

    func deleteGear(id: String) async throws {
        // Optimistic removal
        gear.removeAll { $0.id == id }
        saveToCache(gear, key: gearKey)

        guard isOnline else {
            enqueue(SyncOperation(type: .deleteGear, payload: encodePayload(DeletePayload(id: id))))
            return
        }

        do {
            try await APIService.shared.deleteGear(id: id)
        } catch {
            if isNetworkError(error) {
                enqueue(SyncOperation(type: .deleteGear, payload: encodePayload(DeletePayload(id: id))))
            } else {
                throw error
            }
        }
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
        let packGearIds      = Set(trip.packs.flatMap { $0.items.map { $0.gearId } })
        let bundleIds        = Set(trip.packs.flatMap { $0.bundleRefs.map { $0.bundleId } })
        let referencedBundles = bundles.filter { bundleIds.contains($0.id) }
        let bundleGearIds    = Set(referencedBundles.flatMap { $0.items.map { $0.gearId } })
        let allGearIds       = packGearIds.union(bundleGearIds)

        trip.archived      = true
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
        let tempId = makeTempId()
        let local  = GearBundle(_id: tempId, name: name, items: [])
        bundles.append(local)
        saveToCache(bundles, key: bundlesKey)

        guard isOnline else {
            enqueue(SyncOperation(type: .addBundle, payload: encodePayload(AddBundlePayload(name: name)), localId: tempId))
            return
        }

        do {
            let bundle = try await APIService.shared.createBundle(name: name)
            replaceBundleTempId(tempId, with: bundle)
        } catch {
            if isNetworkError(error) {
                enqueue(SyncOperation(type: .addBundle, payload: encodePayload(AddBundlePayload(name: name)), localId: tempId))
            } else {
                bundles.removeAll { $0.id == tempId }
                saveToCache(bundles, key: bundlesKey)
                throw error
            }
        }
    }

    func updateBundle(id: String, name: String, items: [BundleItem]) async throws {
        let req = BundleRequest(name: name, items: items)

        if let idx = bundles.firstIndex(where: { $0.id == id }) {
            bundles[idx] = GearBundle(_id: id, name: name, items: items)
        }
        saveToCache(bundles, key: bundlesKey)

        guard isOnline else {
            enqueue(SyncOperation(type: .updateBundle, payload: encodePayload(UpdateBundlePayload(id: id, req: req))))
            return
        }

        do {
            let updated = try await APIService.shared.updateBundle(id: id, req: req)
            if let idx = bundles.firstIndex(where: { $0.id == id }) { bundles[idx] = updated }
            saveToCache(bundles, key: bundlesKey)
        } catch {
            if isNetworkError(error) {
                enqueue(SyncOperation(type: .updateBundle, payload: encodePayload(UpdateBundlePayload(id: id, req: req))))
            } else {
                throw error
            }
        }
    }

    func deleteBundle(id: String) async throws {
        bundles.removeAll { $0.id == id }
        saveToCache(bundles, key: bundlesKey)

        guard isOnline else {
            enqueue(SyncOperation(type: .deleteBundle, payload: encodePayload(DeletePayload(id: id))))
            return
        }

        do {
            try await APIService.shared.deleteBundle(id: id)
        } catch {
            if isNetworkError(error) {
                enqueue(SyncOperation(type: .deleteBundle, payload: encodePayload(DeletePayload(id: id))))
            } else {
                throw error
            }
        }
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
        let req    = TripRequest(name: name, destination: destination, startDate: startDate, endDate: endDate, notes: notes, packs: [], archived: false, frozenGear: nil, frozenBundles: nil)
        let tempId = makeTempId()
        let local  = Trip(_id: tempId, name: name, destination: destination, startDate: startDate, endDate: endDate, notes: notes)
        trips.append(local)
        saveToCache(trips, key: tripsKey)

        guard isOnline else {
            enqueue(SyncOperation(type: .addTrip, payload: encodePayload(AddTripPayload(req: req)), localId: tempId))
            return
        }

        do {
            let trip = try await APIService.shared.createTrip(req)
            replaceTripTempId(tempId, with: trip)
        } catch {
            if isNetworkError(error) {
                enqueue(SyncOperation(type: .addTrip, payload: encodePayload(AddTripPayload(req: req)), localId: tempId))
            } else {
                trips.removeAll { $0.id == tempId }
                saveToCache(trips, key: tripsKey)
                throw error
            }
        }
    }

    func updateTrip(_ trip: Trip) async throws {
        // Always apply locally first
        if let idx = trips.firstIndex(where: { $0.id == trip.id }) {
            trips[idx] = trip
        }
        saveToCache(trips, key: tripsKey)

        let req = TripRequest(name: trip.name, destination: trip.destination,
                              startDate: trip.startDate, endDate: trip.endDate,
                              notes: trip.notes, packs: trip.packs,
                              archived: trip.archived,
                              frozenGear: trip.frozenGear, frozenBundles: trip.frozenBundles)

        guard isOnline && !isTempId(trip.id) else {
            enqueue(SyncOperation(type: .updateTrip, payload: encodePayload(UpdateTripPayload(id: trip.id, req: req))))
            return
        }

        do {
            var updated = try await APIService.shared.updateTrip(id: trip.id, req: req)
            // Server may not have archived schema yet — preserve local values
            if trip.archived && !updated.archived {
                updated.archived      = trip.archived
                updated.frozenGear    = trip.frozenGear
                updated.frozenBundles = trip.frozenBundles
            }
            if let idx = trips.firstIndex(where: { $0.id == trip.id }) {
                trips[idx] = updated
            }
            saveToCache(trips, key: tripsKey)
        } catch {
            if isNetworkError(error) {
                enqueue(SyncOperation(type: .updateTrip, payload: encodePayload(UpdateTripPayload(id: trip.id, req: req))))
            } else {
                throw error
            }
        }
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
        trips.removeAll { $0.id == id }
        saveToCache(trips, key: tripsKey)

        guard isOnline else {
            enqueue(SyncOperation(type: .deleteTrip, payload: encodePayload(DeletePayload(id: id))))
            return
        }

        do {
            try await APIService.shared.deleteTrip(id: id)
        } catch {
            if isNetworkError(error) {
                enqueue(SyncOperation(type: .deleteTrip, payload: encodePayload(DeletePayload(id: id))))
            } else {
                throw error
            }
        }
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
        if let idx = pendingCatalog.firstIndex(where: { $0.id == id }) { pendingCatalog[idx] = updated }
        if let idx = catalog.firstIndex(where: { $0.id == id }) { catalog[idx] = updated }
    }
}
