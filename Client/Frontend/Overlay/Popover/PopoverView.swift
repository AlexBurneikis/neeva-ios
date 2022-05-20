// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Shared
import SwiftUI

struct PopoverView<Content: View>: View {
    @State private var title: LocalizedStringKey? = nil

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let style: OverlayStyle
    let onDismiss: () -> Void
    let headerButton: OverlayHeaderButton?
    let content: () -> Content

    var horizontalPadding: CGFloat {
        paddingForSizeClass(horizontalSizeClass)
    }

    var verticalPadding: CGFloat {
        paddingForSizeClass(verticalSizeClass)
    }

    var body: some View {
        GeometryReader { geo in
            VStack {
                SheetHeaderButtonView(headerButton: headerButton, onDismiss: onDismiss)

                VStack {
                    if style.showTitle, let title = title {
                        SheetHeaderView(title: title, onDismiss: onDismiss)
                    }

                    ScrollView(.vertical, showsIndicators: false) {
                        content()
                            .onPreferenceChange(OverlayTitlePreferenceKey.self) {
                                self.title = $0
                            }
                    }
                }
                .padding(14)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .background(
                    Color(style.backgroundColor)
                        .cornerRadius(16)
                )
                // 60 is button height + VStack padding
                .frame(
                    minWidth: 400,
                    maxWidth: geo.size.width - (horizontalPadding * 2),
                    maxHeight: geo.size.height - verticalPadding - 60,
                    alignment: .center
                )
                .fixedSize(horizontal: !style.expandPopoverWidth, vertical: true)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .accessibilityAction(.escape, onDismiss)
        }
    }

    func paddingForSizeClass(_ sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        if let sizeClass = sizeClass, case .regular = sizeClass {
            return 50
        } else {
            return 12
        }
    }
}
