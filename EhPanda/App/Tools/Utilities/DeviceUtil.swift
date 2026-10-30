//
//  DeviceUtil.swift
//  EhPanda
//

import SwiftUI
import Foundation
import Observation

struct DeviceUtil {
    static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    static var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    // Covers iPad and the iPhone Duo inner display (626pt short side),
    // while every other iPhone (440pt at most) stays below it.
    static var isPadWidth: Bool {
        windowW >= 600
    }

    static var isSEWidth: Bool {
        windowW <= 320
    }

    static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .filter({ $0.activationState == .foregroundActive })
            .compactMap({ $0 as? UIWindowScene }).last?
            .windows.filter({ $0.isKeyWindow }).last
    }
    static var anyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).last?
            .windows.last
    }

    // The inner display of iPhone Duo doesn't honor supported interface orientations,
    // so compare the window's dimensions instead of reading the interface orientation.
    static var isLandscape: Bool {
        absWindowW > absWindowH
    }

    static var windowW: CGFloat {
        min(absWindowW, absWindowH)
    }

    static var windowH: CGFloat {
        max(absWindowW, absWindowH)
    }

    static var absWindowW: CGFloat {
        windowSize.width
    }

    static var absWindowH: CGFloat {
        windowSize.height
    }

    // Reading `WindowGeometry.shared.size` registers an observation dependency,
    // so views that use these metrics re-render when the window resizes,
    // e.g. when iPhone Duo folds or unfolds.
    private static var windowSize: CGSize {
        let observedSize = WindowGeometry.shared.size
        return (keyWindow ?? anyWindow)?.frame.size ?? observedSize
    }
}

// MARK: WindowGeometry
@Observable final class WindowGeometry {
    static let shared = WindowGeometry()
    private(set) var size: CGSize = .zero

    func update() {
        guard let newSize = DeviceUtil.keyWindow?.frame.size, newSize != size else { return }
        size = newSize
    }
}
