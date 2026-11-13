import AnalyticsClient
import AppModels
import ComposableArchitecture
import Foundation
import LANraragiClient
import LibraryClient
@testable import SettingFeature
import Sharing
import Testing

// Covers the tag-translation file-import flow: the button drives a native `.fileImporter` through a
// `@Presents` destination, so present/dismiss are exhaustively assertable in the reducer.
// @MainActor sits on members, never on this type: TCA's `TestStore.init` and `.state` are
// main-actor-isolated, so every store-driving case needs it. Annotating the type instead would
// make the suite's protocol conformances main-actor-isolated too (see 11-22-SUMMARY.md).
// Any case left unannotated is deliberately free to run off the main actor.
@Suite
struct GeneralSettingReducerTests {
    @MainActor
    @Test
    func importButtonPresentsFileImporter() async {
        let store = TestStore(initialState: .init(), reducer: GeneralSettingReducer.init) {
            $0.analyticsClient = .noop
        }

        await store.send(.importCustomTranslationsButtonTapped) {
            $0.destination = .importTranslations
        }

        // Cancelling or picking flips the `isPresented` binding back to false → dismiss.
        await store.send(.destination(.dismiss)) {
            $0.destination = nil
        }
    }

    @MainActor
    @Test
    func filePickedCausesNoLocalStateChange() async {
        let store = TestStore(initialState: .init(), reducer: GeneralSettingReducer.init) {
            $0.analyticsClient = .noop
        }

        // The child only relays the URL and mutates no local state; the import itself is handled by
        // `SettingReducer` (covered by `generalFilePickedImportsAndStoresTagTranslator`).
        await store.send(.onTranslationsFilePicked(URL(filePath: "/tmp/tags.json")))
    }
}

/// One call the analytics client received, in the order it came.
private enum AnalyticsCall: Equatable {
    case apply(AnalyticsLevel?)
    case send(AnalyticsSignal)
}

// Covers the analytics level picker (UI-SPEC C-9, D-07, DD-09a): a pick writes the level and applies it to the
// analytics client once, from the reducer, so lowering to Minimal stops the SDK at once (threat T-18-18).
@Suite
struct GeneralSettingAnalyticsLevelTests {
    /// The levels `apply` was called with and the signals `send` was called with, and the order of the two.
    private final class AppliedLevels: Sendable {
        let levels = LockIsolated<[AnalyticsLevel?]>([])
        let signals = LockIsolated<[AnalyticsSignal]>([])
        let calls = LockIsolated<[AnalyticsCall]>([])

        var client: AnalyticsClient {
            var client = AnalyticsClient.noop
            client.apply = { [levels, calls] level in
                levels.withValue({ $0.append(level) })
                calls.withValue({ $0.append(.apply(level)) })
            }
            client.send = { [signals, calls] signal in
                signals.withValue({ $0.append(signal) })
                calls.withValue({ $0.append(.send(signal)) })
            }
            return client
        }
    }

    @MainActor
    @Test(arguments: [
        (stored: AnalyticsLevel.full, picked: AnalyticsLevel.minimal),
        (stored: .basic, picked: .minimal),
        (stored: .minimal, picked: .basic),
        (stored: .minimal, picked: .full),
        (stored: .full, picked: .basic)
    ])
    func pickingALevelStoresItAndAppliesItOnce(stored: AnalyticsLevel, picked: AnalyticsLevel) async {
        let defaults = UserDefaults.inMemory
        let applied = AppliedLevels()
        await withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            let state = GeneralSettingReducer.State()
            state.$setting.withLock({ $0.analyticsLevel = stored })
            let store = TestStore(initialState: state, reducer: GeneralSettingReducer.init) {
                $0.analyticsClient = applied.client
                $0.defaultAppStorage = defaults
            }

            await store.send(.analyticsLevelPicked(picked)) {
                $0.$setting.withLock({ $0.analyticsLevel = picked })
            }
            await store.finish()

            #expect(applied.levels.value == [picked])
            @Shared(.setting) var persisted
            #expect(persisted.analyticsLevel == picked)
        }
    }

    // The change is reported after the new level is applied, as the old and the new level (20-12). A move to Minimal
    // stops the SDK and Minimal promises only the install signal, so it reports nothing.
    @MainActor
    @Test(arguments: [
        (stored: AnalyticsLevel.full, picked: AnalyticsLevel.minimal),
        (stored: .basic, picked: .minimal),
        (stored: .minimal, picked: .basic),
        (stored: .minimal, picked: .full),
        (stored: .full, picked: .basic),
        (stored: .basic, picked: .full)
    ])
    func pickingALevelSendsTheChangeAfterApplyingIt(stored: AnalyticsLevel, picked: AnalyticsLevel) async {
        let defaults = UserDefaults.inMemory
        let applied = AppliedLevels()
        await withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            let state = GeneralSettingReducer.State()
            state.$setting.withLock({ $0.analyticsLevel = stored })
            let store = TestStore(initialState: state, reducer: GeneralSettingReducer.init) {
                $0.analyticsClient = applied.client
                $0.defaultAppStorage = defaults
            }

            await store.send(.analyticsLevelPicked(picked)) {
                $0.$setting.withLock({ $0.analyticsLevel = picked })
            }
            await store.finish()

            let changed: [AnalyticsCall] = picked == .minimal
                ? []
                : [.send(.analyticsLevelChanged(from: stored, toLevel: picked))]
            #expect(applied.calls.value == [.apply(picked)] + changed)
        }
    }

    @MainActor
    @Test(arguments: AnalyticsLevel.allCases)
    func pickingTheCurrentLevelAgainAppliesNothing(level: AnalyticsLevel) async {
        let defaults = UserDefaults.inMemory
        let applied = AppliedLevels()
        await withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            let state = GeneralSettingReducer.State()
            state.$setting.withLock({ $0.analyticsLevel = level })
            let store = TestStore(initialState: state, reducer: GeneralSettingReducer.init) {
                $0.analyticsClient = applied.client
                $0.defaultAppStorage = defaults
            }

            await store.send(.analyticsLevelPicked(level))
            await store.finish()

            #expect(applied.levels.value.isEmpty)
            #expect(applied.signals.value.isEmpty)
        }
    }

    @MainActor
    @Test
    func noOtherActionAppliesALevel() async {
        let defaults = UserDefaults.inMemory
        let applied = AppliedLevels()
        await withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            let state = GeneralSettingReducer.State()
            state.$setting.withLock({ $0.analyticsLevel = .basic })
            let store = TestStore(initialState: state, reducer: GeneralSettingReducer.init) {
                $0.analyticsClient = applied.client
                $0.defaultAppStorage = defaults
            }
            store.exhaustivity = .off

            await store.send(.importCustomTranslationsButtonTapped)
            await store.send(.destination(.dismiss))
            await store.send(.onTranslationsFilePicked(URL(filePath: "/tmp/tags.json")))
            await store.send(.removeCustomTranslationsButtonTapped)
            await store.send(.clearImageCacheButtonTapped)
            await store.send(.calculateWebImageDiskCacheDone(2048))
            await store.send(.delegate(.enableTagsExtensionChanged))
            await store.finish()

            #expect(applied.levels.value.isEmpty)
            #expect(applied.signals.value.isEmpty)
        }
    }
}

// Covers the LANraragi section: the API key is read from the keychain when General is presented and written
// back on each edit, and Test Connection reports the server's answer beside the button.
@Suite
struct GeneralSettingLANraragiTests {
    /// The keys `setAPIKey` was called with, in order.
    private final class StoredKeys: Sendable {
        let values = LockIsolated<[String]>([])
    }

    private static func client(
        storedKey: String = "",
        storedKeys: StoredKeys = StoredKeys(),
        verify: @escaping @Sendable (String, String) async -> Result<Void, LANraragiError> = { _, _ in .success(()) }
    ) -> LANraragiClient {
        var client = LANraragiClient.noop
        client.apiKey = { storedKey }
        client.setAPIKey = { key in storedKeys.values.withValue({ $0.append(key) }) }
        client.verifyConnection = verify
        return client
    }

    @MainActor
    @Test
    func presentingReadsTheStoredKey() async {
        let store = TestStore(initialState: .init(), reducer: GeneralSettingReducer.init) {
            $0.lanraragiClient = Self.client(storedKey: "stored-key")
            $0.libraryClient = .noop
        }

        await store.send(.onPresented) {
            $0.lanraragiAPIKey = "stored-key"
        }
        await store.receive(\.calculateWebImageDiskCache)
        await store.receive(\.calculateWebImageDiskCacheDone)
    }

    @MainActor
    @Test
    func editingTheKeyStoresItAndResetsTheCheck() async {
        let storedKeys = StoredKeys()
        var state = GeneralSettingReducer.State()
        state.lanraragiConnectionState = .verified
        let store = TestStore(initialState: state, reducer: GeneralSettingReducer.init) {
            $0.lanraragiClient = Self.client(storedKeys: storedKeys)
        }

        await store.send(.binding(.set(\.lanraragiAPIKey, "new-key"))) {
            $0.lanraragiAPIKey = "new-key"
            $0.lanraragiConnectionState = .idle
        }
        await store.finish()
        #expect(storedKeys.values.value == ["new-key"])
    }

    @MainActor
    @Test(arguments: [
        (Result<Void, LANraragiError>.success(()), GeneralSettingReducer.LANraragiConnectionState.verified),
        (.failure(.unauthorized), .failed),
        (.failure(.networkingFailed), .failed)
    ])
    func testConnectionShowsTheOutcome(
        result: Result<Void, LANraragiError>, expected: GeneralSettingReducer.LANraragiConnectionState
    ) async {
        let requests = LockIsolated<[String]>([])
        // The server address lives in `@Shared(.setting)`; an in-memory store keeps it from other tests.
        let defaults = UserDefaults.inMemory
        let store = withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            var state = GeneralSettingReducer.State()
            state.lanraragiAPIKey = "key"
            state.$setting.withLock({ $0.lanraragiServerURL = "nas.local:3000" })
            return TestStore(initialState: state, reducer: GeneralSettingReducer.init) {
                $0.defaultAppStorage = defaults
                $0.lanraragiClient = Self.client { serverURL, apiKey in
                    requests.withValue({ $0.append("\(serverURL) \(apiKey)") })
                    return result
                }
            }
        }

        await store.send(.testLANraragiConnectionButtonTapped) {
            $0.lanraragiConnectionState = .verifying
        }
        await store.receive(\.testLANraragiConnectionDone) {
            $0.lanraragiConnectionState = expected
        }
        #expect(requests.value == ["nas.local:3000 key"])
    }

    @MainActor
    @Test
    func changingTheServerResetsTheCheck() async {
        var state = GeneralSettingReducer.State()
        state.lanraragiConnectionState = .failed
        let store = TestStore(initialState: state, reducer: GeneralSettingReducer.init)

        await store.send(.lanraragiServerURLChanged) {
            $0.lanraragiConnectionState = .idle
        }
    }
}
