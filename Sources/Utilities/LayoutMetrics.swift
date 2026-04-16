import CoreGraphics
import Foundation

/// Simple layout constants (replacement for deleted Design/LayoutMetrics)
internal enum LayoutMetrics {
    enum DashboardWindow {
        static let width: CGFloat = 900
        static let height: CGFloat = 600
        static let initialSize = CGSize(width: 900, height: 600)
        static let minimumSize = CGSize(width: 700, height: 500)
        static let previewSize = CGSize(width: 900, height: 600)
    }

    enum FloatingDock {
        static let collapsedSize = CGSize(width: 50, height: 18)
        static let expandedSize = CGSize(width: 340, height: 88)
        static let shortcutCaptureSize = CGSize(width: 76, height: 24)
        static let recordingControlsSize = CGSize(width: 138, height: 40)
        static let bottomOffset: CGFloat = 12
    }
}
