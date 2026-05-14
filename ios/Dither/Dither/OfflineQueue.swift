import Foundation

// MARK: - Operation type

enum SyncOpType: String, Codable {
    case addGear, updateGear, deleteGear
    case addBundle, updateBundle, deleteBundle
    case addTrip, updateTrip, deleteTrip
}

// MARK: - Queued operation

struct SyncOperation: Codable {
    /// Stable identifier used to deduplicate / remove from the queue.
    let id: String
    let type: SyncOpType
    /// JSON-encoded payload specific to the operation type.
    let payload: Data
    /// For add operations: the temporary UUID string that was assigned locally.
    /// nil for update/delete operations.
    let localId: String?
    let createdAt: Date

    init(type: SyncOpType, payload: Data, localId: String? = nil) {
        self.id        = UUID().uuidString
        self.type      = type
        self.payload   = payload
        self.localId   = localId
        self.createdAt = Date()
    }

    /// Build a copy with a patched payload (used when temp IDs are resolved).
    func withPayload(_ data: Data) -> SyncOperation {
        SyncOperation(id: id, type: type, payload: data, localId: localId, createdAt: createdAt)
    }

    private init(id: String, type: SyncOpType, payload: Data, localId: String?, createdAt: Date) {
        self.id        = id
        self.type      = type
        self.payload   = payload
        self.localId   = localId
        self.createdAt = createdAt
    }
}

// MARK: - Payload types
// Each operation encodes a strongly-typed value as the `payload` Data blob.

struct AddGearPayload: Codable {
    let req: GearItemRequest
}
struct UpdateGearPayload: Codable {
    let id: String
    let req: GearItemRequest
}
struct DeletePayload: Codable {
    let id: String
}
struct AddBundlePayload: Codable {
    let name: String
}
struct UpdateBundlePayload: Codable {
    let id: String
    let req: BundleRequest
}
struct AddTripPayload: Codable {
    let req: TripRequest
}
struct UpdateTripPayload: Codable {
    let id: String
    let req: TripRequest
}

// MARK: - Helpers

private let enc = JSONEncoder()
private let dec = JSONDecoder()

func encodePayload<T: Encodable>(_ value: T) -> Data {
    (try? enc.encode(value)) ?? Data()
}

func decodePayload<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    try dec.decode(type, from: data)
}

// MARK: - Temp-ID helpers

let tempIdPrefix = "temp_"

func makeTempId() -> String { "\(tempIdPrefix)\(UUID().uuidString)" }
func isTempId(_ id: String)  -> Bool { id.hasPrefix(tempIdPrefix) }
