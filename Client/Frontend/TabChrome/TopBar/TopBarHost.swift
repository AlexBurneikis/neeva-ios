// Copyright Neeva. All rights reserved.

import Combine
import SwiftUI

// For sharing to work, this must currently be the BrowserViewController
protocol TopBarDelegate: ToolbarDelegate {
    func urlBarReloadMenu() -> UIMenu?
    func urlBarDidPressStop()
    func urlBarDidPressReload()
    func urlBarDidEnterOverlayMode()
    func urlBarDidLeaveOverlayMode()
    func urlBarDidLongPressOverflow(targetButtonView: UIView)
    func urlBar(didSubmitText text: String)

    func perform(neevaMenuAction: NeevaMenuAction)
    func updateFeedbackImage()

    var tabContentHost: TabContentHost { get }
    var tabManager: TabManager { get }
    var searchQueryModel: SearchQueryModel { get }
}

struct TopBarContent: View {
    let suggestionModel: SuggestionModel
    let model: LocationViewModel
    let queryModel: SearchQueryModel
    let gridModel: GridModel
    let trackingStatsViewModel: TrackingStatsViewModel
    let chromeModel: TabChromeModel

    let newTab: () -> Void
    let onCancel: () -> Void

    var body: some View {
        TopBarView(
            performTabToolbarAction: { action in
                chromeModel.topBarDelegate?.performTabToolbarAction(action)
            },
            buildTabsMenu: { chromeModel.topBarDelegate?.tabToolbarTabsMenu() },
            onReload: {
                switch chromeModel.reloadButton {
                case .reload:
                    chromeModel.topBarDelegate?.urlBarDidPressReload()
                case .stop:
                    chromeModel.topBarDelegate?.urlBarDidPressStop()
                }
            },
            onSubmit: { chromeModel.topBarDelegate?.urlBar(didSubmitText: $0) },
            onShare: { shareView in
                // also update in LegacyTabToolbarHelper
                ClientLogger.shared.logCounter(
                    .ClickShareButton, attributes: EnvironmentHelper.shared.getAttributes())
                guard
                    let bvc = chromeModel.topBarDelegate as? BrowserViewController,
                    let tab = bvc.tabManager.selectedTab,
                    let url = tab.url
                else { return }
                if url.isFileURL {
                    bvc.share(fileURL: url, buttonView: shareView, presentableVC: bvc)
                } else {
                    bvc.share(tab: tab, from: shareView, presentableVC: bvc)
                }
            },
            buildReloadMenu: { chromeModel.topBarDelegate?.urlBarReloadMenu() },
            onNeevaMenuAction: { chromeModel.topBarDelegate?.perform(neevaMenuAction: $0) },
            didTapNeevaMenu: { chromeModel.topBarDelegate?.updateFeedbackImage() },
            newTab: newTab,
            onCancel: onCancel,
            onOverflowMenuAction: {
                chromeModel.topBarDelegate?.perform(overflowMenuAction: $0, targetButtonView: $1)
            },
            onLongPressOverflowButton: {
                chromeModel.topBarDelegate?.urlBarDidLongPressOverflow(targetButtonView: $0)
            }
        )
        .environmentObject(suggestionModel)
        .environmentObject(model)
        .environmentObject(queryModel)
        .environmentObject(gridModel)
        .environmentObject(trackingStatsViewModel)
        .environmentObject(chromeModel)
    }
}

class TopBarHost: IncognitoAwareHostingController<TopBarContent> {
    init(
        isIncognito: Bool,
        locationViewModel: LocationViewModel,
        suggestionModel: SuggestionModel,
        queryModel: SearchQueryModel,
        gridModel: GridModel,
        trackingStatsViewModel: TrackingStatsViewModel,
        chromeModel: TabChromeModel,
        delegate: TopBarDelegate,
        newTab: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        super.init(isIncognito: isIncognito)

        setRootView {
            TopBarContent(
                suggestionModel: suggestionModel,
                model: locationViewModel,
                queryModel: queryModel,
                gridModel: gridModel,
                trackingStatsViewModel: trackingStatsViewModel,
                chromeModel: chromeModel,
                newTab: newTab,
                onCancel: onCancel
            )
        }
        self.view.backgroundColor = .clear
        self.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.setContentHuggingPriority(.required, for: .vertical)
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
