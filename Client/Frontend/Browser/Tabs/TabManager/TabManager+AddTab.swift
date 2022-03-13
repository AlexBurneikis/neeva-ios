// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Shared
import Storage
import WebKit

extension TabManager {
    func addTabsForURLs(_ urls: [URL], zombie: Bool) {
        assert(Thread.isMainThread)

        if urls.isEmpty {
            return
        }

        var tab: Tab!
        for url in urls {
            tab = self.addTab(
                URLRequest(url: url), flushToDisk: false, zombie: zombie, notify: false)
        }

        // Select the most recent.
        selectTab(tab)

        // Okay now notify that we bulk-loaded so we can adjust counts and animate changes.
        tabsUpdatedPublisher.send()

        // Flush.
        storeChanges()
    }

    @discardableResult func addTab(
        _ request: URLRequest! = nil, configuration: WKWebViewConfiguration! = nil,
        afterTab: Tab? = nil, isIncognito: Bool = false,
        query: String? = nil, suggestedQuery: String? = nil,
        visitType: VisitType? = nil, notify: Bool = true
    ) -> Tab {
        return self.addTab(
            request, configuration: configuration, afterTab: afterTab, flushToDisk: true,
            zombie: false, isIncognito: isIncognito,
            query: query, suggestedQuery: suggestedQuery,
            visitType: visitType, notify: notify
        )
    }

    func addTab(
        _ request: URLRequest? = nil, webView: WKWebView? = nil,
        configuration: WKWebViewConfiguration? = nil, atIndex: Int? = nil, afterTab: Tab? = nil,
        flushToDisk: Bool, zombie: Bool, isIncognito: Bool = false,
        query: String? = nil, suggestedQuery: String? = nil,
        visitType: VisitType? = nil, notify: Bool = true
    ) -> Tab {
        assert(Thread.isMainThread)

        // Take the given configuration. Or if it was nil, take our default configuration for the current browsing mode.
        let configuration: WKWebViewConfiguration =
            configuration ?? (isIncognito ? incognitoConfiguration : self.configuration)

        let bvc = SceneDelegate.getBVC(with: scene)
        let tab = Tab(bvc: bvc, configuration: configuration, isIncognito: isIncognito)
        configureTab(
            tab, request: request, webView: webView, atIndex: atIndex, afterTab: afterTab,
            flushToDisk: flushToDisk, zombie: zombie,
            query: query, suggestedQuery: suggestedQuery,
            visitType: visitType,
            notify: notify)

        return tab
    }

    func configureTab(
        _ tab: Tab, request: URLRequest?, webView: WKWebView? = nil, atIndex: Int? = nil,
        afterTab parent: Tab? = nil, flushToDisk: Bool, zombie: Bool, isPopup: Bool = false,
        query: String? = nil, suggestedQuery: String? = nil,
        visitType: VisitType? = nil, notify: Bool
    ) {
        assert(Thread.isMainThread)

        // If network is not available webView(_:didCommit:) is not going to be called
        // We should set request url in order to show url in url bar even no network
        tab.setURL(request?.url)

        insertTab(tab, atIndex: atIndex, parent: parent, notify: notify)

        if let webView = webView {
            tab.restore(webView)
        } else if !zombie {
            tab.createWebview()
        }

        tab.navigationDelegate = self.navDelegate
        
        if let query = query {
            tab.queryForNavigation.currentQuery = .init(typed: query, suggested: suggestedQuery)
        }

        if let request = request {
            if let nav = tab.loadRequest(request), let visitType = visitType {
                tab.browserViewController?.recordNavigationInTab(
                    tab, navigation: nav, visitType: visitType
                )
            }
        } else if !isPopup {
            let url = InternalURL.baseUrl / "about" / "home"
            tab.loadRequest(PrivilegedRequest(url: url) as URLRequest)
            tab.setURL(url)
        }

        if flushToDisk {
            storeChanges()
        }
    }

    private func insertTab(_ tab: Tab, atIndex: Int? = nil, parent: Tab? = nil, notify: Bool) {
        if let atIndex = atIndex, atIndex <= tabs.count {
            tabs.insert(tab, at: atIndex)
        } else if parent == nil || parent?.isIncognito != tab.isIncognito {
            var insertIndex: Int? = nil

            for incognitoStateTab in isIncognito ? incognitoTabs : normalTabs {
                if addTabToTabGroupIfNeeded(newTab: tab, possibleChildTab: incognitoStateTab) {
                    guard let childTabIndex = tabs.firstIndex(of: incognitoStateTab) else {
                        continue
                    }

                    // Insert the tab where the child tab is so it appears
                    // before it in the Tab Group.
                    insertIndex = childTabIndex
                }
            }

            if let insertIndex = insertIndex {
                tabs.insert(tab, at: insertIndex)
            } else {
                tabs.append(tab)
            }
        } else if let parent = parent, var insertIndex = tabs.firstIndex(of: parent) {
            insertIndex += 1
            while insertIndex < tabs.count && tabs[insertIndex].isDescendentOf(parent) {
                insertIndex += 1
            }

            tab.parent = parent
            tab.parentUUID = parent.tabUUID
            tab.rootUUID = parent.rootUUID
            tabs.insert(tab, at: insertIndex)
        }

        if notify {
            tabsUpdatedPublisher.send()
        }
    }

    // MARK: - Tab Groups
    /// Checks if the new tab URL matches the origin URL for the tab and if so,
    /// then the two tabs should be in a Tab Group together.
    @discardableResult func addTabToTabGroupIfNeeded(
        newTab: Tab, possibleChildTab: Tab
    ) -> Bool {
        let childTabOriginalURL = possibleChildTab.originalURL?.normalizedHostAndPathForDisplay
        let newTabURL = newTab.url?.normalizedHostAndPathForDisplay
        let shouldCreateTabGroup = childTabOriginalURL == newTabURL

        if shouldCreateTabGroup {
            if possibleChildTab.parent == nil {
                // Create a Tab Group by setting the child tab's rootID.
                possibleChildTab.rootUUID = newTab.rootUUID
            } else {
                // Set the new tab's root ID the same as the current tab,
                // since they should both be in the same Tab Group.
                newTab.rootUUID = possibleChildTab.rootUUID
            }
        }

        return shouldCreateTabGroup
    }

    // MARK: - Restore Tabs
    func restoreSavedTabs(
        _ savedTabs: [SavedTab], isIncognito: Bool = false, shouldSelectTab: Bool = true
    ) -> Tab? {
        // makes sure at least one tab is selected
        // if no tab selected, select the last one (most recently closed)
        var selectedSavedTab: Tab?

        for index in 0..<savedTabs.count {
            let savedTab = savedTabs[index]
            let urlRequest: URLRequest? = savedTab.url != nil ? URLRequest(url: savedTab.url!) : nil

            var tab: Tab!
            if let tabIndex = savedTab.tabIndex {
                tab = addTab(
                    urlRequest, atIndex: tabIndex, flushToDisk: false, zombie: false,
                    isIncognito: isIncognito, notify: false)
            } else {
                tab = addTab(
                    urlRequest, afterTab: getTabForUUID(uuid: savedTab.parentUUID ?? ""),
                    flushToDisk: false, zombie: false, isIncognito: isIncognito, notify: false)
            }

            savedTab.configureTab(tab, imageStore: store.imageStore)
            tab.restore(tab.webView!)

            if savedTab.isSelected {
                selectedSavedTab = tab
            } else if index == savedTabs.count - 1 && selectedSavedTab == nil {
                selectedSavedTab = tab
            }
        }

        tabsUpdatedPublisher.send()

        // Prevents a sticky tab tray
        SceneDelegate.getBVC(with: scene).browserModel.cardTransitionModel.update(to: .hidden)

        if let selectedSavedTab = selectedSavedTab, shouldSelectTab {
            self.selectTab(selectedSavedTab)
        }

        // remove restored tabs from recently closed
        if let index = recentlyClosedTabs.firstIndex(of: savedTabs) {
            recentlyClosedTabs.remove(at: index)
        }

        closedTabsToShowToastFor.removeAll { savedTabs.contains($0) }

        return selectedSavedTab
    }

    func restoreAllClosedTabs() {
        _ = restoreSavedTabs(Array(recentlyClosedTabs.joined()))
    }
}
