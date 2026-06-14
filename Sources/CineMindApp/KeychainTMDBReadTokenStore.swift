import Application
import Foundation
import Security

struct KeychainTMDBReadTokenStore: TMDBReadTokenStoring {
    private let service = "com.cinemind.credentials"
    private let account = "tmdb.read-access-token"

    func readToken() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw KeychainTMDBReadTokenStoreError.operationFailed
        }
        return token
    }

    func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainTMDBReadTokenStoreError.operationFailed
        }

        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw KeychainTMDBReadTokenStoreError.operationFailed
        }
    }

    func deleteToken() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainTMDBReadTokenStoreError.operationFailed
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private enum KeychainTMDBReadTokenStoreError: Error {
    case operationFailed
}
