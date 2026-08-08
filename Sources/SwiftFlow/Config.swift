import Foundation

struct Config: Codable {
    var deepgramApiKey: String
    var cerebrasApiKey: String
    var cerebrasModel: String?
    var cleanupEnabled: Bool?
    var soundsEnabled: Bool?

    static var path: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swiftflow/config.json")
    }

    static func load() -> Config? {
        guard let data = try? Data(contentsOf: path) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(Config.self, from: data)
    }
}
