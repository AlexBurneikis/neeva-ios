// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import SwiftUI

extension Color {
    public init(light: Color, dark: Color) {
        self.init(UIColor(light: UIColor(light), dark: UIColor(dark)))
    }

    /// Create a `Color` with the given hex code
    ///
    /// ```
    /// Color(hex: 0xff0000) // red
    /// ```
    ///
    /// Source: [Stack Overflow](https://stackoverflow.com/a/56894458/5244995)
    public init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 08) & 0xff) / 255,
            blue: Double((hex >> 00) & 0xff) / 255,
            opacity: opacity
        )
    }

    /// Create a `Color` with the given hex code
    ///
    /// ```
    /// Image(...).foregroundColor(.hex(0xff0000))
    /// ```
    public static func hex(_ hex: UInt, opacity: Double = 1) -> Color {
        Color(hex: hex, opacity: opacity)
    }
}
