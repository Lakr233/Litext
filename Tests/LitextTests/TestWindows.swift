//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

#if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)

    import UIKit

    /// Windows kept alive after the test that showed them.
    ///
    /// Views can outlive a window released at the end of a test: UIKit's selection
    /// UI, the highlight, the handles and the loupe, animates away after the selection
    /// ends, and a label stays alive while work it scheduled is pending. They still
    /// refer to the window, so a later test's layout pass crashes inside
    /// `-[UIView _updateSafeAreaInsets]`.
    @MainActor
    enum TestWindows {
        private static var windows: [UIWindow] = []

        /// Keeps `window` alive for the rest of the test run.
        static func keepAlive(_ window: UIWindow) {
            windows.append(window)
        }
    }

#endif
