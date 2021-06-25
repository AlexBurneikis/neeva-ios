// Copyright Neeva. All rights reserved.

import Foundation
import Shared

class ReadingModeActivity: UIActivity {
    private let readerModeState: ReaderModeState?
    fileprivate let callback: () -> Void

    init(readerModeState: ReaderModeState, callback: @escaping () -> Void) {
        self.readerModeState = readerModeState
        self.callback = callback
    }

    override var activityTitle: String? {
        if readerModeState == .available {
            return Strings.ShowReadingModeTitleActivity
        }

        return Strings.HideReadingModeTitleActivity
    }

    override var activityImage: UIImage? {
        return #imageLiteral(resourceName: "reader")
    }

    override func perform() {
        callback()
        activityDidFinish(true)
    }

    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        return true
    }
}
