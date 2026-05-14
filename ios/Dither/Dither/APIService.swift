import Foundation

// MARK: - API Error
enum APIError: LocalizedError {
    case invalidURL
    case noData
    case decodingError(Error)
    case serverError(Int, String)
    case unauthorized
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .noData: return "No data returned"
        case .decodingError(let e): return "Decoding error: \(e.localizedDescription)"
        case .serverError(let code, let msg): return "Server error \(code): \(msg)"
        case .unauthorized: return "Unauthorized — please log in again"
        case .networkError(let e): return e.localizedDescription
        }
    }
}

// MARK: - API Service
class APIService {
    static let shared = APIService()
    let base = "https://dither.fish"
    var token: String?

    private init() {}

    // MARK: - Core request
    func request<T: Decodable>(_ path: String, method: String = "GET", body: Encodable? = nil) async throws -> T {
        guard let url = URL(string: base + path) else {
            throw APIError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            req.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.networkError(error)
        }

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw APIError.serverError(httpResponse.statusCode, msg)
            }
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Void request (no response body needed)
    func requestVoid(_ path: String, method: String = "GET", body: Encodable? = nil) async throws {
        guard let url = URL(string: base + path) else {
            throw APIError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            req.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.networkError(error)
        }

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw APIError.serverError(httpResponse.statusCode, msg)
            }
        }
    }

    // MARK: - Convenience
    func get<T: Decodable>(_ path: String) async throws -> T {
        try await request(path, method: "GET")
    }

    func post<T: Decodable>(_ path: String, body: Encodable) async throws -> T {
        try await request(path, method: "POST", body: body)
    }

    func put<T: Decodable>(_ path: String, body: Encodable) async throws -> T {
        try await request(path, method: "PUT", body: body)
    }

    func delete(_ path: String) async throws {
        try await requestVoid(path, method: "DELETE")
    }

    // MARK: - Auth
    func login(username: String, password: String) async throws -> AuthResponse {
        struct LoginBody: Encodable {
            let username: String
            let password: String
        }
        return try await post("/api/auth/login", body: LoginBody(username: username, password: password))
    }

    func register(username: String, password: String) async throws -> AuthResponse {
        struct RegisterBody: Encodable {
            let username: String
            let password: String
        }
        return try await post("/api/auth/register", body: RegisterBody(username: username, password: password))
    }

    // MARK: - Gear
    func fetchGear() async throws -> [GearItem] {
        try await get("/api/gear")
    }

    func createGear(_ item: GearItemRequest) async throws -> GearItem {
        try await post("/api/gear", body: item)
    }

    func updateGear(id: String, item: GearItemRequest) async throws -> GearItem {
        try await put("/api/gear/\(id)", body: item)
    }

    func deleteGear(id: String) async throws {
        try await delete("/api/gear/\(id)")
    }

    // MARK: - Bundles
    func fetchBundles() async throws -> [GearBundle] {
        try await get("/api/bundles")
    }

    func createBundle(name: String) async throws -> GearBundle {
        struct NameBody: Encodable { let name: String }
        return try await post("/api/bundles", body: NameBody(name: name))
    }

    func updateBundle(id: String, req: BundleRequest) async throws -> GearBundle {
        try await put("/api/bundles/\(id)", body: req)
    }

    func deleteBundle(id: String) async throws {
        try await delete("/api/bundles/\(id)")
    }

    // MARK: - Trips
    func fetchTrips() async throws -> [Trip] {
        try await get("/api/trips")
    }

    func createTrip(_ req: TripRequest) async throws -> Trip {
        try await post("/api/trips", body: req)
    }

    func updateTrip(id: String, req: TripRequest) async throws -> Trip {
        try await put("/api/trips/\(id)", body: req)
    }

    func deleteTrip(id: String) async throws {
        try await delete("/api/trips/\(id)")
    }

    // MARK: - Catalog
    func fetchCatalog() async throws -> [CatalogItem] {
        try await get("/api/catalog")
    }

    func suggestCatalogItem(_ req: CatalogSuggestRequest) async throws {
        try await requestVoid("/api/catalog/suggest", method: "POST", body: req)
    }

    func fetchPendingCatalog() async throws -> [CatalogItem] {
        try await get("/api/catalog/pending")
    }

    func approveCatalogItem(id: String) async throws {
        try await requestVoid("/api/catalog/\(id)/approve", method: "PUT")
    }

    func deleteCatalogItem(id: String) async throws {
        try await delete("/api/catalog/\(id)")
    }

    func editCatalogItem(id: String, req: CatalogEditRequest) async throws -> CatalogItem {
        try await put("/api/catalog/\(id)", body: req)
    }
}
