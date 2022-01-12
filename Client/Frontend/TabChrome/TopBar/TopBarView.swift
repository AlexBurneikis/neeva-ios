// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Defaults
import Shared
import SwiftUI

struct TopBarView: View {
    let performTabToolbarAction: (ToolbarAction) -> Void
    let buildTabsMenu: () -> UIMenu?
    let onReload: () -> Void
    let onSubmit: (String) -> Void
    let onShare: (UIView) -> Void
    let buildReloadMenu: () -> UIMenu?
    let onNeevaMenuAction: (NeevaMenuAction) -> Void
    let didTapNeevaMenu: () -> Void
    let newTab: () -> Void
    let onCancel: () -> Void
    let onOverflowMenuAction: (OverflowMenuAction, UIView) -> Void

    @State private var shouldInsetHorizontally = false
    @State private var opacity: Double = 1

    @EnvironmentObject private var chrome: TabChromeModel
    @EnvironmentObject private var location: LocationViewModel

    private var separator: some View {
        Color.ui.adaptive.separator.frame(height: 0.5).ignoresSafeArea()
    }

    var body: some View {
        VStack(spacing: 0) {
            if UIConstants.enableBottomURLBar {
                separator.padding(.bottom, chrome.inlineToolbar ? 0 : 3)
            }

            HStack(spacing: chrome.inlineToolbar ? 12 : 0) {
                if chrome.inlineToolbar {
                    TabToolbarButtons.BackButton(
                        weight: .regular,
                        onBack: { performTabToolbarAction(.back) },
                        onLongPress: { performTabToolbarAction(.longPressBackForward) }
                    ).tapTargetFrame()

                    TabToolbarButtons.ForwardButton(
                        weight: .regular,
                        onForward: { performTabToolbarAction(.forward) },
                        onLongPress: { performTabToolbarAction(.longPressBackForward) }
                    ).tapTargetFrame()

                    TabToolbarButtons.ReloadStopButton(
                        weight: .regular,
                        onTap: { performTabToolbarAction(.reloadStop) }
                    ).tapTargetFrame()

                    TopBarOverflowMenuButton(
                        changedUserAgent:
                            chrome.topBarDelegate?.tabManager.selectedTab?.showRequestDesktop,
                        onOverflowMenuAction: onOverflowMenuAction,
                        location: .tab
                    )
                }
                TabLocationView(
                    onReload: onReload, onSubmit: onSubmit, onShare: onShare,
                    buildReloadMenu: buildReloadMenu, onCancel: onCancel
                )
                .padding(.horizontal, chrome.inlineToolbar ? 0 : 8)
                .padding(.top, chrome.inlineToolbar ? 8 : 3)
                // -1 for the progress bar
                .padding(.bottom, (chrome.inlineToolbar ? 8 : 10) - 1)
                .layoutPriority(1)
                if chrome.inlineToolbar {
                    TopBarNeevaMenuButton(
                        onTap: {
                            chrome.hideZeroQuery()
                            didTapNeevaMenu()
                        }, onNeevaMenuAction: onNeevaMenuAction)

                    TabToolbarButtons.AddToSpace(
                        weight: .regular, action: { performTabToolbarAction(.addToSpace) }
                    )
                    .tapTargetFrame()

                    TabToolbarButtons.ShowTabs(
                        weight: .regular, action: { performTabToolbarAction(.showTabs) },
                        buildMenu: buildTabsMenu
                    )
                    .tapTargetFrame()
                }
            }
            /// Unfortunately `.opacity(chrome.controlOpacity)` doesn't work consistently.
            /// Sometimes SwiftUI will not notice updates to `controlOpacity`. Directly
            /// observing `controlOpacity` here seems to do the trick. /Sigh/
            .onReceive(chrome.$controlOpacity) { value in
                opacity = value
            }
            .opacity(opacity)
            .padding(.horizontal, shouldInsetHorizontally ? 12 : 0)
            .padding(.bottom, chrome.estimatedProgress == nil ? 0 : -1)

            if chrome.showTopCardStrip {
                GeometryReader { geo in
                    CardStripContent(
                        bvc: SceneDelegate.getBVC(with: chrome.topBarDelegate?.tabManager.scene),
                        width: geo.size.width)
                }
            }

            ZStack {
                if let progress = chrome.estimatedProgress {
                    ProgressView(value: progress)
                        .progressViewStyle(PageProgressBarStyle())
                        .padding(.bottom, -1)
                        .ignoresSafeArea(edges: .horizontal)
                }
            }
            .zIndex(1)
            .transition(.opacity)
            .animation(.spring(), value: chrome.estimatedProgress)

            if !UIConstants.enableBottomURLBar {
                separator
            }
        }
        .background(
            GeometryReader { geom in
                let shouldInsetHorizontally =
                    geom.safeAreaInsets.leading == 0 && geom.safeAreaInsets.trailing == 0
                    && chrome.inlineToolbar
                Color.clear
                    .useEffect(deps: shouldInsetHorizontally) { self.shouldInsetHorizontally = $0 }
            }
        )
        .background(Color.DefaultBackground.ignoresSafeArea())
        .accentColor(.label)
    }
}
