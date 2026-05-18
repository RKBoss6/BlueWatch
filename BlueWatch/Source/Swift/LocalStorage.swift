//
//  LocalStorage.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 4/6/26.
//

import Foundation

class LocalStorage {
    static func set(_ value: Any, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
    static func getBool(forKey key: String) -> Bool? {
        return UserDefaults.standard.bool(forKey: key)
    }
    static func getNumber(forKey key: String) -> Double? {
        return UserDefaults.standard.double(forKey: key)
    }
    static func getString(forKey key: String) -> String? {
        return UserDefaults.standard.string(forKey: key) ?? ""
    }
}
