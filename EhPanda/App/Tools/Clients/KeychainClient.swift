//
//  KeychainClient.swift
//  EhPanda
//

import Security
import Foundation
import ComposableArchitecture

enum KeychainKey: String {
    case lanraragiAPIKey
}

struct KeychainClient {
    let string: (KeychainKey) -> String?
    let setString: (String, KeychainKey) -> Void
}

extension KeychainClient {
    static let live: Self = .init(
        string: { key in
            var query = baseQuery(key: key)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne

            var result: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                  let data = result as? Data
            else { return nil }
            return String(data: data, encoding: .utf8)
        },
        setString: { value, key in
            let query = baseQuery(key: key)
            SecItemDelete(query as CFDictionary)
            guard !value.isEmpty else { return }

            var attributes = query
            attributes[kSecValueData as String] = Data(value.utf8)
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(attributes as CFDictionary, nil)
        }
    )

    private static func baseQuery(key: KeychainKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "app.ehpanda",
            kSecAttrAccount as String: key.rawValue
        ]
    }
}

// MARK: API
enum KeychainClientKey: DependencyKey {
    static let liveValue = KeychainClient.live
    static let previewValue = KeychainClient.noop
    static let testValue = KeychainClient.unimplemented
}

extension DependencyValues {
    var keychainClient: KeychainClient {
        get { self[KeychainClientKey.self] }
        set { self[KeychainClientKey.self] = newValue }
    }
}

// MARK: Test
extension KeychainClient {
    static let noop: Self = .init(
        string: { _ in nil },
        setString: { _, _ in }
    )

    static func placeholder<Result>() -> Result { fatalError() }

    static let unimplemented: Self = .init(
        string: IssueReporting.unimplemented(placeholder: placeholder()),
        setString: IssueReporting.unimplemented(placeholder: placeholder())
    )
}
