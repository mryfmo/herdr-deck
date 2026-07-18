import Foundation

enum GatewayJSONCoding {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        // Gateway responses include both its own camelCase records and Herdr's
        // normalized snake_case records. This strategy accepts the latter
        // without changing camelCase keys that contain no underscore.
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        // Public HerdDeck HTTP request bodies are camelCase. Snake case is an
        // implementation detail of the Gateway ↔ Herdr socket boundary.
        JSONEncoder()
    }
}