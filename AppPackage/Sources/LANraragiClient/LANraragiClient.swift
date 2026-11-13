public import ComposableArchitecture
public import Foundation
import Security

/// Sends galleries to the user's LANraragi server, and keeps that server's API key in the keychain.
///
/// Requests go through their own ephemeral session, so the app's domain fronting and E-Hentai cookies
/// are never applied to them.
public struct LANraragiClient: Sendable {
    public var apiKey: @Sendable () -> String
    public var setAPIKey: @Sendable (String) -> Void
    public var verifyConnection: @Sendable (_ serverURL: String, _ apiKey: String) async -> Result<Void, LANraragiError>
    public var queueDownload: @Sendable (_ serverURL: String, _ galleryURL: URL) async -> Result<Void, LANraragiError>

    public init(
        apiKey: @escaping @Sendable () -> String,
        setAPIKey: @escaping @Sendable (String) -> Void,
        verifyConnection: @escaping @Sendable (_ serverURL: String, _ apiKey: String) async
            -> Result<Void, LANraragiError>,
        queueDownload: @escaping @Sendable (_ serverURL: String, _ galleryURL: URL) async
            -> Result<Void, LANraragiError>
    ) {
        self.apiKey = apiKey
        self.setAPIKey = setAPIKey
        self.verifyConnection = verifyConnection
        self.queueDownload = queueDownload
    }
}

extension LANraragiClient {
    public static let live: Self = .init(
        apiKey: { KeychainStore.string(account: KeychainStore.apiKeyAccount) ?? "" },
        setAPIKey: { KeychainStore.setString($0, account: KeychainStore.apiKeyAccount) },
        verifyConnection: { serverURL, apiKey in
            guard let request = LANraragiAPI.verifyRequest(serverURL: serverURL, apiKey: apiKey) else {
                return .failure(.invalidServerURL)
            }
            return await perform(request).flatMap { response in
                LANraragiAPI.verifyResult(statusCode: response.statusCode)
            }
        },
        queueDownload: { serverURL, galleryURL in
            let apiKey = KeychainStore.string(account: KeychainStore.apiKeyAccount) ?? ""
            guard let request = LANraragiAPI.queueDownloadRequest(
                serverURL: serverURL, apiKey: apiKey, galleryURL: galleryURL
            ) else {
                return .failure(.invalidServerURL)
            }
            return await perform(request).flatMap { response in
                LANraragiAPI.queueDownloadResult(statusCode: response.statusCode, data: response.data)
            }
        }
    )

    private struct HTTPResponse: Sendable {
        let statusCode: Int
        let data: Data
    }

    private static let session = URLSession(configuration: .ephemeral)

    private static func perform(_ request: URLRequest) async -> Result<HTTPResponse, LANraragiError> {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return .failure(.unexpectedResponse) }
            return .success(HTTPResponse(statusCode: httpResponse.statusCode, data: data))
        } catch {
            // A refused connection, a timeout or an unknown host: the server could not be reached.
            return .failure(.networkingFailed)
        }
    }
}

// MARK: Keychain
private enum KeychainStore {
    static let apiKeyAccount = "lanraragiAPIKey"

    static func string(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Replaces the stored value; an empty one removes it.
    static func setString(_ value: String, account: String) {
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }

        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "app.ehpanda",
            kSecAttrAccount as String: account
        ]
    }
}

// MARK: API
public enum LANraragiClientKey: DependencyKey {
    public static let liveValue = LANraragiClient.live
    public static let previewValue = LANraragiClient.noop
    public static let testValue = LANraragiClient.unimplemented
}

extension DependencyValues {
    public var lanraragiClient: LANraragiClient {
        get { self[LANraragiClientKey.self] }
        set { self[LANraragiClientKey.self] = newValue }
    }
}

// MARK: Test
extension LANraragiClient {
    public static let noop: Self = .init(
        apiKey: { "" },
        setAPIKey: { _ in },
        verifyConnection: { _, _ in .success(()) },
        queueDownload: { _, _ in .success(()) }
    )

    public static func placeholder<Result>() -> Result { fatalError() }

    public static let unimplemented: Self = .init(
        apiKey: IssueReporting.unimplemented(placeholder: placeholder()),
        setAPIKey: IssueReporting.unimplemented(placeholder: placeholder()),
        verifyConnection: IssueReporting.unimplemented(placeholder: placeholder()),
        queueDownload: IssueReporting.unimplemented(placeholder: placeholder())
    )
}
