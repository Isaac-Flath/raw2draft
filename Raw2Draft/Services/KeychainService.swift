import Foundation

/// Protocol for key-value storage of API keys and config.
protocol KeychainServiceProtocol {
    func getKey(_ key: KeychainKey) -> String?
    func setKey(_ key: KeychainKey, value: String) throws
    func deleteKey(_ key: KeychainKey) throws
    func getKeyStatuses() -> [(key: KeychainKey, present: Bool)]
    func hydrateEnvironment(_ env: inout [String: String])

    /// URL of the backing .env file.
    var envFileURL: URL { get }

    /// Read the raw .env file contents.
    func readEnvFile() -> String

    /// Write raw .env file contents, parsing and saving all keys.
    func writeEnvFile(_ contents: String) throws
}

/// Reads and writes API keys from a `.env` file at ~/Documents/Raw2Draft/.env.
final class KeychainService: KeychainServiceProtocol {
    let envFileURL: URL

    /// In-memory cache of parsed key-value pairs.
    private var cache: [String: String] = [:]
    private let lock = NSLock()

    init(envFileURL: URL = Constants.defaultContentPlatformRoot.appendingPathComponent(".env")) {
        self.envFileURL = envFileURL
        loadFromDisk()
    }

    // MARK: - Public API

    func getKey(_ key: KeychainKey) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let value = cache[key.rawValue]
        return (value?.isEmpty ?? true) ? nil : value
    }

    func setKey(_ key: KeychainKey, value: String) throws {
        lock.lock()
        cache[key.rawValue] = value
        lock.unlock()
        try saveToDisk()
    }

    func deleteKey(_ key: KeychainKey) throws {
        lock.lock()
        cache.removeValue(forKey: key.rawValue)
        lock.unlock()
        try saveToDisk()
    }

    func getKeyStatuses() -> [(key: KeychainKey, present: Bool)] {
        KeychainKey.allCases.map { key in
            (key: key, present: getKey(key) != nil)
        }
    }

    func hydrateEnvironment(_ env: inout [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        for key in KeychainKey.environmentKeys {
            if env[key.rawValue] != nil { continue }
            if let value = cache[key.rawValue], !value.isEmpty {
                env[key.rawValue] = value
            }
        }
    }

    // MARK: - .env File I/O

    func readEnvFile() -> String {
        loadFromDisk()
        lock.lock()
        defer { lock.unlock() }

        // Build .env text from all known keys, preserving order
        var lines: [String] = []
        for key in KeychainKey.apiKeys {
            let value = cache[key.rawValue] ?? ""
            lines.append("\(key.rawValue)=\(value)")
        }

        return lines.joined(separator: "\n")
    }

    func writeEnvFile(_ contents: String) throws {
        lock.lock()
        // Clear existing cache and re-parse
        cache.removeAll()
        parseEnvContents(contents)
        lock.unlock()
        try saveToDisk()
    }

    // MARK: - Private

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: envFileURL.path) else { return }
        guard let contents = try? String(contentsOf: envFileURL, encoding: .utf8) else { return }

        lock.lock()
        cache.removeAll()
        parseEnvContents(contents)
        lock.unlock()
    }

    /// Parse .env format into cache. Caller must hold lock.
    private func parseEnvContents(_ contents: String) {
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            guard let equalsIndex = trimmed.firstIndex(of: "=") else { continue }

            let key = String(trimmed[trimmed.startIndex..<equalsIndex])
                .trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: equalsIndex)...])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

            if !key.isEmpty {
                cache[key] = value
            }
        }
    }

    private func saveToDisk() throws {
        // Ensure directory exists
        let dir = envFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        lock.lock()
        var lines: [String] = []
        // Write known keys first (in order), then any extras
        var written = Set<String>()
        for key in KeychainKey.allCases {
            if let value = cache[key.rawValue] {
                lines.append("\(key.rawValue)=\(value)")
            }
            written.insert(key.rawValue)
        }
        // Write any unknown keys that were in the file
        for (key, value) in cache.sorted(by: { $0.key < $1.key }) where !written.contains(key) {
            lines.append("\(key)=\(value)")
        }
        lock.unlock()

        let content = lines.joined(separator: "\n") + "\n"
        try content.write(to: envFileURL, atomically: true, encoding: .utf8)
    }
}

// MARK: - Errors

enum KeychainError: LocalizedError {
    case unableToStore(status: OSStatus)
    case unableToDelete(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .unableToStore(let status):
            return "Unable to store item (status: \(status))"
        case .unableToDelete(let status):
            return "Unable to delete item (status: \(status))"
        }
    }
}
