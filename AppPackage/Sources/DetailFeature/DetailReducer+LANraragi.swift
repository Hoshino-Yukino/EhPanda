import AppComponents
import ComposableArchitecture
import Foundation
import HapticsClient
import LANraragiClient

// MARK: - Send to LANraragi
// Queues the gallery in the user's LANraragi downloader without leaving the app. The toast shows the request
// while it runs and then its outcome.
extension DetailReducer {
    var lanraragiReducer: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .sendToLANraragiButtonTapped:
                let serverURL = state.setting.lanraragiServerURL
                guard !serverURL.isEmpty, let galleryURL = state.gallery.galleryURL else { return .none }
                state.toast = .communicating
                return .run { send in
                    switch await lanraragiClient.queueDownload(serverURL, galleryURL) {
                    case .success:
                        await send(.sendToLANraragiDone(nil))
                    case .failure(let error):
                        await send(.sendToLANraragiDone(error))
                    }
                }
                .cancellable(id: CancelID.sendToLANraragi(state.cancellationGalleryID), cancelInFlight: true)

            case .sendToLANraragiDone(let error):
                if let error {
                    state.toast = .error(caption: error.caption)
                    return .run(operation: { _ in await hapticsClient.generateNotificationFeedback(.error) })
                }
                state.toast = .success(caption: .lanraragiQueued)
                return .run(operation: { _ in await hapticsClient.generateNotificationFeedback(.success) })

            case .toast:
                return .none

            default:
                return .none
            }
        }
    }
}

private extension LANraragiError {
    var caption: LocalizedStringResource {
        switch self {
        case .invalidServerURL: .lanraragiErrorInvalidServerAddress
        case .networkingFailed: .lanraragiErrorUnreachable
        case .unauthorized: .lanraragiErrorUnauthorized
        case .unexpectedResponse: .lanraragiErrorRejected
        }
    }
}
