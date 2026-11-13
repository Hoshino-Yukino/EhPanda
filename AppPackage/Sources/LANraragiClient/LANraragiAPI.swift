public import Foundation

/// Why a LANraragi request did not succeed.
public enum LANraragiError: Error, Equatable, Sendable {
    /// The server address in Settings does not form a URL.
    case invalidServerURL
    /// The server could not be reached.
    case networkingFailed
    /// The server refused the API key (HTTP 401).
    case unauthorized
    /// The server answered, but not with a success.
    case unexpectedResponse
}

/// Builds the LANraragi API requests and reads their responses. Kept free of any session so it can be
/// tested without the network.
public enum LANraragiAPI {
    /// The URL of `/api/<path>` on the server the user entered. A missing scheme reads as `http`, since
    /// LANraragi servers are usually reached over plain HTTP on the local network.
    public static func endpoint(serverURL: String, path: String) -> URL? {
        var base = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }
        if !base.contains("://") {
            base = "http://" + base
        }
        while base.hasSuffix("/") {
            base.removeLast()
        }
        guard let url = URL(string: "\(base)/api/\(path)"), url.host() != nil else { return nil }
        return url
    }

    /// `GET /api/shinobu`, which, unlike `/api/info`, needs the API key, so it checks both the address
    /// and the key.
    public static func verifyRequest(serverURL: String, apiKey: String) -> URLRequest? {
        guard let url = endpoint(serverURL: serverURL, path: "shinobu") else { return nil }
        var request = URLRequest(url: url)
        request.setAuthorization(apiKey: apiKey)
        return request
    }

    /// `POST /api/download_url?url=<galleryURL>`, which queues the gallery in LANraragi's downloader.
    public static func queueDownloadRequest(serverURL: String, apiKey: String, galleryURL: URL) -> URLRequest? {
        // Encode the characters that would otherwise split or end the query.
        var allowedCharacters = CharacterSet.urlQueryAllowed
        allowedCharacters.remove(charactersIn: "&=+?#")
        guard let url = endpoint(serverURL: serverURL, path: "download_url"),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let encodedGalleryURL = galleryURL.absoluteString.addingPercentEncoding(
                withAllowedCharacters: allowedCharacters
              )
        else { return nil }
        components.percentEncodedQueryItems = [URLQueryItem(name: "url", value: encodedGalleryURL)]
        guard let requestURL = components.url else { return nil }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setAuthorization(apiKey: apiKey)
        return request
    }

    /// The outcome of the connection check from its HTTP status.
    public static func verifyResult(statusCode: Int) -> Result<Void, LANraragiError> {
        switch statusCode {
        case 200: .success(())
        case 401: .failure(.unauthorized)
        default: .failure(.unexpectedResponse)
        }
    }

    /// The outcome of queueing a download: the server must answer 200 with `"success": 1`.
    public static func queueDownloadResult(statusCode: Int, data: Data) -> Result<Void, LANraragiError> {
        guard statusCode == 200 else {
            return .failure(statusCode == 401 ? .unauthorized : .unexpectedResponse)
        }
        do {
            let response = try JSONDecoder().decode(QueueDownloadResponse.self, from: data)
            return response.success == 1 ? .success(()) : .failure(.unexpectedResponse)
        } catch {
            // Any other body is not LANraragi's answer to this request.
            return .failure(.unexpectedResponse)
        }
    }

    private struct QueueDownloadResponse: Decodable {
        let success: Int
    }
}

private extension URLRequest {
    /// LANraragi reads the API key as a Base64-encoded Bearer token. No key means no header, which a
    /// server without a key set accepts.
    mutating func setAuthorization(apiKey: String) {
        guard !apiKey.isEmpty else { return }
        setValue("Bearer " + Data(apiKey.utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
    }
}
