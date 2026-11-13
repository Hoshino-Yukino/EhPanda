import Foundation
import LANraragiClient
import Testing

@Suite
struct LANraragiAPITests {
    // MARK: Endpoint

    @Test(arguments: [
        ("192.168.1.2:3000", "http://192.168.1.2:3000/api/shinobu"),
        ("  http://nas.local:3000/  ", "http://nas.local:3000/api/shinobu"),
        ("https://lrr.example.com//", "https://lrr.example.com/api/shinobu"),
        ("https://example.com/lrr", "https://example.com/lrr/api/shinobu")
    ])
    func endpointNormalizesTheServerAddress(serverURL: String, expected: String) {
        #expect(LANraragiAPI.endpoint(serverURL: serverURL, path: "shinobu")?.absoluteString == expected)
    }

    @Test(arguments: ["", "   ", "http://"])
    func endpointRejectsAnAddressWithoutAHost(serverURL: String) {
        #expect(LANraragiAPI.endpoint(serverURL: serverURL, path: "shinobu") == nil)
    }

    // MARK: Requests

    @Test
    func verifyRequestSendsTheKeyAsABase64BearerToken() throws {
        let request = try #require(LANraragiAPI.verifyRequest(serverURL: "nas.local:3000", apiKey: "secret"))
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "http://nas.local:3000/api/shinobu")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer c2VjcmV0")
    }

    @Test
    func requestsWithoutAKeyCarryNoAuthorization() throws {
        let request = try #require(LANraragiAPI.verifyRequest(serverURL: "nas.local:3000", apiKey: ""))
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test
    func queueDownloadRequestPostsTheEncodedGalleryURL() throws {
        let galleryURL = try #require(URL(string: "https://e-hentai.org/g/123/abc/?p=1&x=a+b#top"))
        let request = try #require(
            LANraragiAPI.queueDownloadRequest(serverURL: "nas.local:3000", apiKey: "secret", galleryURL: galleryURL)
        )
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer c2VjcmV0")
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/api/download_url")
        #expect(
            components.percentEncodedQuery
                == "url=https://e-hentai.org/g/123/abc/%3Fp%3D1%26x%3Da%2Bb%23top"
        )
        #expect(components.queryItems?.first?.value == galleryURL.absoluteString)
    }

    @Test
    func queueDownloadRequestNeedsAServerAddress() throws {
        let galleryURL = try #require(URL(string: "https://e-hentai.org/g/123/abc/"))
        #expect(LANraragiAPI.queueDownloadRequest(serverURL: "", apiKey: "", galleryURL: galleryURL) == nil)
    }

    // MARK: Responses

    @Test
    func verifyResultReadsTheStatusCode() {
        #expect(LANraragiAPI.verifyResult(statusCode: 200).isSuccess)
        #expect(LANraragiAPI.verifyResult(statusCode: 401).failure == .unauthorized)
        #expect(LANraragiAPI.verifyResult(statusCode: 500).failure == .unexpectedResponse)
    }

    @Test
    func queueDownloadResultNeedsSuccessInTheBody() {
        let queued = Data(#"{"operation":"download_url","success":1,"job":42}"#.utf8)
        let refused = Data(#"{"operation":"download_url","success":0,"error":"no"}"#.utf8)
        #expect(LANraragiAPI.queueDownloadResult(statusCode: 200, data: queued).isSuccess)
        #expect(LANraragiAPI.queueDownloadResult(statusCode: 200, data: refused).failure == .unexpectedResponse)
        let page = Data("<html>".utf8)
        #expect(LANraragiAPI.queueDownloadResult(statusCode: 200, data: page).failure == .unexpectedResponse)
        #expect(LANraragiAPI.queueDownloadResult(statusCode: 401, data: Data()).failure == .unauthorized)
        #expect(LANraragiAPI.queueDownloadResult(statusCode: 404, data: queued).failure == .unexpectedResponse)
    }
}

private extension Result where Success == Void {
    var isSuccess: Bool {
        switch self {
        case .success: true
        case .failure: false
        }
    }

    var failure: Failure? {
        switch self {
        case .success: nil
        case .failure(let error): error
        }
    }
}
