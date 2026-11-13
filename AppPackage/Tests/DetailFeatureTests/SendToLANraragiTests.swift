import AppComponents
import AppModels
import ComposableArchitecture
@testable import DetailFeature
import Foundation
import HapticsClient
import LANraragiClient
import Sharing
import Testing

// Send to LANraragi queues the gallery URL on the server set in Settings, and the toast shows the request and then
// its outcome.
//
// @MainActor sits on members, never on this type: TCA's `TestStore.init` and `.state` are main-actor-isolated.
@Suite
struct SendToLANraragiTests {
    private static let galleryURL = URL.mock.appending(path: "g/42/abc123/")

    @MainActor
    @Test
    func aQueuedGalleryShowsSuccess() async {
        let requests = LockIsolated<[String]>([])
        let store = makeStore(serverURL: "nas.local:3000") { serverURL, galleryURL in
            requests.withValue({ $0.append("\(serverURL) \(galleryURL.absoluteString)") })
            return .success(())
        }

        await store.send(.sendToLANraragiButtonTapped) {
            $0.toast = .communicating
        }
        await store.receive(\.sendToLANraragiDone) {
            $0.toast = .success(caption: .lanraragiQueued)
        }
        #expect(requests.value == ["nas.local:3000 \(Self.galleryURL.absoluteString)"])
    }

    @MainActor
    @Test(arguments: [
        (LANraragiError.invalidServerURL, LocalizedStringResource.lanraragiErrorInvalidServerAddress),
        (.networkingFailed, .lanraragiErrorUnreachable),
        (.unauthorized, .lanraragiErrorUnauthorized),
        (.unexpectedResponse, .lanraragiErrorRejected)
    ])
    func aFailureShowsWhy(error: LANraragiError, caption: LocalizedStringResource) async {
        let store = makeStore(serverURL: "nas.local:3000") { _, _ in .failure(error) }

        await store.send(.sendToLANraragiButtonTapped) {
            $0.toast = .communicating
        }
        await store.receive(\.sendToLANraragiDone) {
            $0.toast = .error(caption: caption)
        }
    }

    @MainActor
    @Test
    func withoutAServerNothingIsSent() async {
        // The menu hides the item without a server; the reducer refuses it all the same.
        let store = makeStore(serverURL: "") { _, _ in
            Issue.record("Nothing should be sent without a server")
            return .success(())
        }

        await store.send(.sendToLANraragiButtonTapped)
    }

    @MainActor
    private func makeStore(
        serverURL: String,
        queueDownload: @escaping @Sendable (String, URL) async -> Result<Void, LANraragiError>
    ) -> TestStoreOf<DetailReducer> {
        // The server address lives in `@Shared(.setting)`; an in-memory store keeps it from other tests.
        let defaults = UserDefaults.inMemory
        return withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            @Shared(.setting) var setting
            $setting.withLock({ $0.lanraragiServerURL = serverURL })
            let state = DetailReducer.State(
                gallery: Gallery(
                    gid: "42", token: "abc123", title: "Seed", rating: 4.5, tags: [],
                    category: .doujinshi, pageCount: 30, postedDate: .init(timeIntervalSince1970: 0),
                    coverURL: nil, galleryURL: Self.galleryURL
                )
            )
            var lanraragiClient = LANraragiClient.noop
            lanraragiClient.queueDownload = queueDownload
            return TestStore(initialState: state, reducer: DetailReducer.init) {
                $0.defaultAppStorage = defaults
                $0.hapticsClient = .noop
                $0.lanraragiClient = lanraragiClient
            }
        }
    }
}
