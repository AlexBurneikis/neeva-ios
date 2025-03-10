// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Shared
import SwiftUI

enum DefaultBrowserPromoRules {
    static let nthZeroQueryImpression = 4
    static let maxDailyPromoImpression = 3
    static let hoursAfterInterstitialForPromoCard = 72
}

enum AppRatingPromoCardRule {
    static let numOfAppForegroundLastWeek = 3
}

enum AppRatingSystemDialogRule {
    static let numOfAppForeground = 6
}

enum PromoCardType {
    case previewModeSignUp(action: () -> Void, onClose: () -> Void)
    case neevaSignIn(action: () -> Void)
    case defaultBrowser(action: () -> Void, onClose: () -> Void)
    case referralPromo(action: () -> Void, onClose: () -> Void)
    case notificationPermission(action: () -> Void, onClose: () -> Void)
    case walletPromo(action: () -> Void)

    var action: () -> Void {
        switch self {
        case .previewModeSignUp(let action, _), .neevaSignIn(let action):
            return action
        case .defaultBrowser(let action, _):
            return action
        case .referralPromo(let action, _):
            return action
        case .notificationPermission(let action, _):
            return action
        case .walletPromo(let action):
            return action
        }
    }

    @ViewBuilder
    var title: some View {
        switch self {
        case .previewModeSignUp:
            Text("Get the most out of Neeva's private search and browsing.")
        case .neevaSignIn:
            Text("Get safer, richer and better\nsearch when you sign in")
        case .defaultBrowser:
            Text("Get the most out of Neeva's private search and browsing.")
        case .referralPromo:
            (Text("Win ") + Text("$5000").fontWeight(.medium)
                + Text(" by inviting friends to join Neeva"))
                .fixedSize(horizontal: false, vertical: true)
        case .notificationPermission:
            Text("From news to shopping,\nget the best of the web\ndelivered right to you")
        case .walletPromo:
            Text(verbatim: "Experience Web3,\n with clarity and safety")
        }
    }

    @ViewBuilder
    var buttonLabel: some View {
        switch self {
        case .previewModeSignUp, .neevaSignIn:
            HStack(spacing: 8) {
                Image("neevaMenuIcon")
                    .renderingMode(.template)
                    .frame(width: 18, height: 16)
                Text("Sign in or Join Neeva")
                    .padding(.horizontal, 20)
            }
        case .defaultBrowser:
            HStack(spacing: 8) {
                Image("neevaMenuIcon")
                    .renderingMode(.template)
                    .frame(width: 18, height: 16)
                Text("Set as Default Browser")
                    .padding(.horizontal, 20)
            }
        case .referralPromo:
            HStack(spacing: 8) {
                Text("Tell me more")
                Symbol(decorative: .arrowRight, weight: .semibold)
            }
        case .notificationPermission:
            Text("Enable Notifications")
        case .walletPromo:
            Text(verbatim: "Create / Import Wallet")
        }
    }

    var color: Color {
        switch self {
        case .previewModeSignUp, .neevaSignIn, .notificationPermission, .defaultBrowser:
            return .brand.adaptive.polar
        case .referralPromo:
            return Color(light: .hex(0xFFEAD1), dark: .hex(0xF8C991))
        case .walletPromo:
            return .quaternarySystemFill
        }
    }

    var isCompact: Bool {
        switch self {
        case .referralPromo:
            return true
        default:
            return false
        }
    }

    var name: String {
        switch self {
        case .previewModeSignUp:
            return "previewModeSignUp"
        case .neevaSignIn:
            return "neevaSignIn"
        case .defaultBrowser:
            return "defaultBrowser"
        case .referralPromo:
            return "referralPromo"
        case .notificationPermission:
            return "notificationPermission"
        case .walletPromo:
            return "walletPromo"
        }
    }
}

struct PromoCard: View {
    let type: PromoCardType
    var viewWidth: CGFloat

    // this number is from the Figma mock
    let minimumButtonWidth: CGFloat = 250

    @ViewBuilder
    var button: some View {
        #if XYZ
            Button(action: type.action) {
                type
                    .buttonLabel
                    .frame(maxWidth: .infinity)
            }.buttonStyle(.wallet(.primary))
        #else
            Button(action: type.action) {
                if type.isCompact {
                    HStack {
                        type.buttonLabel
                        Spacer()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.brand.blue)
                } else {
                    HStack {
                        Spacer()
                        type.buttonLabel
                        Spacer()
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(height: 48)
                    .background(Capsule().fill(Color.brand.blue))
                }
            }
        #endif
    }

    @ViewBuilder
    var label: some View {
        let size: CGFloat = type.isCompact ? 20 : 24
        let lineSpacing = 32 - size

        type.title
            .font(.roobert(.regular, size: size))
            .lineSpacing(lineSpacing)
            .foregroundColorOrGradient(.hex(0x131415))
            .padding(.vertical, type.isCompact ? 0 : lineSpacing)
    }

    @ViewBuilder
    var closeButton: some View {
        if case .defaultBrowser(_, let onClose) = type {
            Button(action: onClose) {
                Symbol(.xmark, weight: .semibold, label: "Dismiss")
                    .foregroundColor(Color.ui.gray70)
            }
        } else if case .referralPromo(_, let onClose) = type {
            Button(action: onClose) {
                Symbol(.xmark, weight: .semibold, label: "Dismiss")
                    .foregroundColor(Color.ui.gray70)
            }
        } else if case .notificationPermission(_, let onClose) = type {
            Button(action: onClose) {
                Symbol(.xmark, weight: .semibold, label: "Dismiss")
                    .foregroundColor(Color.ui.gray70)
            }
        } else if case .previewModeSignUp(_, let onClose) = type {
            Button(action: onClose) {
                Symbol(.xmark, weight: .semibold, label: "Dismiss")
                    .foregroundColor(Color.ui.gray70)
            }
        }
    }

    var background: some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        let innerShadowAmount: CGFloat = 1.25
        return
            shape
            .fill(type.color)
            .background(
                shape
                    .fill(Color.black.opacity(0.03))
                    .blur(radius: 0.5)
                    .offset(y: -0.5)
            )
            .overlay(
                // Reference: https://www.hackingwithswift.com/plus/swiftui-special-effects/shadows-and-glows
                shape
                    .inset(by: -innerShadowAmount)
                    .stroke(Color.black.opacity(0.2), lineWidth: innerShadowAmount * 2)
                    .blur(radius: 0.5)
                    .offset(y: -innerShadowAmount)
                    .mask(shape)
            )

    }

    var isHorizontal: Bool {
        if case .referralPromo = type {
            return false
        }

        // button takes up roughly 1/2.5 of the view width
        return viewWidth / 2.5 > minimumButtonWidth
    }

    var body: some View {
        Group {
            if isHorizontal {
                HStack {
                    label
                    Spacer()
                    button
                    closeButton
                }
            } else {
                VStack(spacing: 16) {
                    HStack(alignment: .top) {
                        label
                        Spacer()
                        closeButton
                    }
                    button
                }
            }
        }
        .padding(25)
        .background(background)
        .frame(maxWidth: 650)
        .padding()
    }
}

struct PromoCard_Previews: PreviewProvider {
    static var previews: some View {
        ForEach(
            Array(
                [
                    .neevaSignIn(action: {}), .defaultBrowser(action: {}, onClose: {}),
                    .referralPromo(action: {}, onClose: {}),
                ].enumerated()), id: \.0
        ) { (card: (Int, PromoCardType)) in
            GeometryReader { geom in
                PromoCard(type: card.1, viewWidth: geom.size.width)
            }
        }.previewLayout(.sizeThatFits)
    }
}
