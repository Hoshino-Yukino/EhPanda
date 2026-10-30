//
//  GeneralSettingReducer.swift
//  EhPanda
//

import Kingfisher
import LocalAuthentication
import ComposableArchitecture

@Reducer
struct GeneralSettingReducer {
    @CasePathable
    enum Route {
        case logs
        case clearCache
        case removeCustomTranslations
    }

    enum LANraragiConnectionState: Equatable {
        case idle
        case verifying
        case verified
        case failed
    }

    private enum CancelID {
        case verifyLANraragiConnection
    }

    @ObservableState
    struct State: Equatable {
        var route: Route?

        var loadingState: LoadingState = .idle
        var diskImageCacheSize = "0 KB"
        var passcodeNotSet = false

        var lanraragiAPIKey = ""
        var lanraragiConnectionState: LANraragiConnectionState = .idle

        var logsState = LogsReducer.State()
    }

    enum Action: BindableAction, Equatable {
        case binding(BindingAction<State>)
        case setNavigation(Route?)
        case clearSubStates
        case onTranslationsFilePicked(URL)
        case onRemoveCustomTranslations

        case clearWebImageCache
        case checkPasscodeSetting
        case navigateToSystemSetting
        case calculateWebImageDiskCache
        case calculateWebImageDiskCacheDone(UInt?)

        case loadLANraragiAPIKey
        case resetLANraragiConnectionState
        case verifyLANraragiConnection(String)
        case verifyLANraragiConnectionDone(Bool)

        case logs(LogsReducer.Action)
    }

    @Dependency(\.authorizationClient) private var authorizationClient
    @Dependency(\.uiApplicationClient) private var uiApplicationClient
    @Dependency(\.databaseClient) private var databaseClient
    @Dependency(\.libraryClient) private var libraryClient
    @Dependency(\.keychainClient) private var keychainClient

    var body: some Reducer<State, Action> {
        BindingReducer()
            .onChange(of: \.route) { _, newValue in
                Reduce({ _, _ in newValue == nil ? .send(.clearSubStates) : .none })
            }
            .onChange(of: \.lanraragiAPIKey) { _, newValue in
                Reduce { state, _ in
                    state.lanraragiConnectionState = .idle
                    return .run(operation: { _ in keychainClient.setString(newValue, .lanraragiAPIKey) })
                }
            }

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .setNavigation(let route):
                state.route = route
                return route == nil ? .send(.clearSubStates) : .none

            case .clearSubStates:
                state.logsState = .init()
                return .send(.logs(.teardown))

            case .onTranslationsFilePicked:
                return .none

            case .onRemoveCustomTranslations:
                return .none

            case .clearWebImageCache:
                return .merge(
                    .run(operation: { _ in libraryClient.clearWebImageDiskCache() }),
                    .run(operation: { _ in await databaseClient.removeImageURLs() }),
                    .send(.calculateWebImageDiskCache)
                )

            case .checkPasscodeSetting:
                state.passcodeNotSet = authorizationClient.passcodeNotSet()
                return .none

            case .navigateToSystemSetting:
                return .run(operation: { _ in await uiApplicationClient.openSettings() })

            case .calculateWebImageDiskCache:
                return .run { send in
                    let size = await libraryClient.calculateWebImageDiskCacheSize()
                    await send(.calculateWebImageDiskCacheDone(size))
                }

            case .calculateWebImageDiskCacheDone(let bytes):
                guard let bytes = bytes else { return .none }
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = .useAll
                state.diskImageCacheSize = formatter.string(fromByteCount: .init(bytes))
                return .none

            case .loadLANraragiAPIKey:
                state.lanraragiAPIKey = keychainClient.string(.lanraragiAPIKey) ?? ""
                return .none

            case .resetLANraragiConnectionState:
                state.lanraragiConnectionState = .idle
                return .cancel(id: CancelID.verifyLANraragiConnection)

            case .verifyLANraragiConnection(let serverURL):
                state.lanraragiConnectionState = .verifying
                return .run { [apiKey = state.lanraragiAPIKey] send in
                    let response = await VerifyLANraragiRequest(serverURL: serverURL, apiKey: apiKey).response()
                    if case .success = response {
                        await send(.verifyLANraragiConnectionDone(true))
                    } else {
                        await send(.verifyLANraragiConnectionDone(false))
                    }
                }
                .cancellable(id: CancelID.verifyLANraragiConnection, cancelInFlight: true)

            case .verifyLANraragiConnectionDone(let isVerified):
                state.lanraragiConnectionState = isVerified ? .verified : .failed
                return .none

            case .logs:
                return .none
            }
        }

        Scope(state: \.logsState, action: \.logs, child: LogsReducer.init)
    }
}
