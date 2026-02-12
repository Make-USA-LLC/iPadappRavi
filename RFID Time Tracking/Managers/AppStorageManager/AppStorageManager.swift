//
//  AppStorageManager.swift
//  RFID Time Tracking
//
//

import Foundation

final class AppStateStorageManager {

    static let shared = AppStateStorageManager()
    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - SAVE

    func save<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    func save(_ value: Any, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    // MARK: - LOAD

    func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func loadBool(forKey key: String) -> Bool {
        defaults.bool(forKey: key)
    }

    func loadInt(forKey key: String) -> Int {
        defaults.integer(forKey: key)
    }

    func loadString(forKey key: String) -> String {
        defaults.string(forKey: key) ?? ""
    }

    func loadDate(forKey key: String) -> Date? {
        defaults.object(forKey: key) as? Date
    }

    // MARK: - CLEAR

    func remove(_ key: String) {
        defaults.removeObject(forKey: key)
    }
}

