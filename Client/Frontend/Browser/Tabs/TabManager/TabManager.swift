/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Combine
import Defaults
import Foundation
import Shared
import Storage
import WebKit
import XCGLogger

private let log = Logger.browser

// TabManager must extend NSObjectProtocol in order to implement WKNavigationDelegate
class TabManager: NSObject, TabEventHandler, WKNavigationDelegate {
    let tabEventHandlers: [TabEventHandler]
    let store: TabManagerStore
    var scene: UIScene
    let profile: Profile
    let incognitoModel: IncognitoModel

    var isIncognito: Bool {
        incognitoModel.isIncognito
    }

    let delaySelectingNewPopupTab: TimeInterval = 0.1

    static var all = WeakList<TabManager>()

    var tabs = [Tab]()
    var tabsUpdatedPublisher = PassthroughSubject<Void, Never>()

    // Tab Group related variables
    @Default(.tabGroupNames) private var tabGroupDict: [String: String]
    @Default(.archivedTabsDuration) var archivedTabsDuration
    var activeTabs: [Tab] = []
    var archivedTabs: [Tab] = []
    var activeTabGroups: [String: TabGroup] = [:]
    var archivedTabGroups: [String: TabGroup] = [:]
    var childTabs: [Tab] {
        activeTabGroups.values.flatMap(\.children)
    }

    // Use `selectedTabPublisher` to observe changes to `selectedTab`.
    private(set) var selectedTab: Tab?
    private(set) var selectedTabPublisher = CurrentValueSubject<Tab?, Never>(nil)
    /// A publisher that forwards the url from the current selectedTab
    private(set) var selectedTabURLPublisher = CurrentValueSubject<URL?, Never>(nil)
    /// Publisher used to observe changes to the `selectedTab.webView`.
    /// Will also update if the `WebView` is set to nil.
    private(set) var selectedTabWebViewPublisher = CurrentValueSubject<WKWebView?, Never>(nil)
    /// A publisher that refreshes data in ArchivedTabsPanelModel, which should happen after
    ///  updateAllTabDataAndSendNotifications runs.
    private(set) var updateArchivedTabsPublisher = PassthroughSubject<Void, Never>()
    private var selectedTabSubscription: AnyCancellable?
    private var selectedTabURLSubscription: AnyCancellable?
    private var archivedTabsDurationSubscription: AnyCancellable?

    let navDelegate: TabManagerNavDelegate

    // A WKWebViewConfiguration used for normal tabs
    lazy var configuration: WKWebViewConfiguration = {
        return TabManager.makeWebViewConfig(isIncognito: false)
    }()

    // A WKWebViewConfiguration used for private mode tabs
    lazy var incognitoConfiguration: WKWebViewConfiguration = {
        return TabManager.makeWebViewConfig(isIncognito: true)
    }()

    // Enables undo of recently closed tabs
    /// Supports closing/restoring a group of tabs or a single tab (alone in an array)
    var recentlyClosedTabs = [[SavedTab]]()
    var recentlyClosedTabsFlattened: [SavedTab] {
        Array(recentlyClosedTabs.joined()).filter {
            !InternalURL.isValid(url: ($0.url ?? URL(string: "")))
        }
    }

    // groups tabs closed together in a certain amount of time into one Toast
    let toastGroupTimerInterval: TimeInterval = 1.5
    var timerToTabsToast: Timer?
    var closedTabsToShowToastFor = [SavedTab]()

    var normalTabs: [Tab] {
        assert(Thread.isMainThread)
        return tabs.filter { !$0.isIncognito }
    }

    var incognitoTabs: [Tab] {
        assert(Thread.isMainThread)
        return tabs.filter { $0.isIncognito }
    }

    var activeNormalTabs: [Tab] {
        return activeTabs.filter { !$0.isIncognito }
    }

    var todaysTabs: [Tab] {
        return activeNormalTabs.filter { $0.wasLastExecuted(.today) }
    }

    var count: Int {
        assert(Thread.isMainThread)

        return tabs.count
    }

    var cookieCutterModel: CookieCutterModel?

    // MARK: - Init
    init(profile: Profile, scene: UIScene, incognitoModel: IncognitoModel) {
        assert(Thread.isMainThread)
        self.profile = profile
        self.navDelegate = TabManagerNavDelegate()
        self.tabEventHandlers = TabEventHandlers.create()
        self.store = TabManagerStore.shared
        self.scene = scene
        self.incognitoModel = incognitoModel
        super.init()

        Self.all.insert(self)

        register(self, forTabEvents: .didLoadFavicon, .didChangeContentBlocking)

        addNavigationDelegate(self)

        NotificationCenter.default.addObserver(
            self, selector: #selector(prefsDidChange), name: UserDefaults.didChangeNotification,
            object: nil)

        ScreenCaptureHelper.defaultHelper.subscribeToTabUpdates(
            from: selectedTabPublisher.eraseToAnyPublisher()
        )

        selectedTabSubscription =
            selectedTabPublisher
            .sink { [weak self] tab in
                self?.selectedTabURLSubscription?.cancel()
                if tab == nil {
                    self?.selectedTabURLPublisher.send(nil)
                }
                self?.selectedTabURLSubscription = tab?.$url
                    .sink {
                        self?.selectedTabURLPublisher.send($0)
                    }
            }

        archivedTabsDurationSubscription =
            _archivedTabsDuration.publisher.dropFirst().sink {
                [weak self] _ in
                self?.updateAllTabDataAndSendNotifications(notify: false)
                // update CardGrid and ArchivedTabsPanelView with the latest data
                self?.updateArchivedTabsPublisher.send()
            }
    }

    func addNavigationDelegate(_ delegate: WKNavigationDelegate) {
        assert(Thread.isMainThread)

        self.navDelegate.insert(delegate)
    }

    subscript(index: Int) -> Tab? {
        assert(Thread.isMainThread)

        if index >= tabs.count {
            return nil
        }
        return tabs[index]
    }

    subscript(webView: WKWebView) -> Tab? {
        assert(Thread.isMainThread)

        for tab in tabs where tab.webView === webView {
            return tab
        }

        return nil
    }

    // MARK: - Get Tab
    func getTabFor(_ url: URL, with parent: Tab? = nil) -> Tab? {
        assert(Thread.isMainThread)

        let options: [URL.EqualsOption] = [
            .normalizeHost, .ignoreFragment, .ignoreLastSlash, .ignoreScheme,
        ]

        log.info(
            "Looking for matching tab, url: \(url) under parent tab: \(String(describing: tab))"
        )

        let incognito = self.isIncognito
        return tabs.first { tab in
            guard tab.isIncognito == incognito else {
                return false
            }

            // Tab.url will be nil if the Tab is yet to be restored.
            if let tabURL = tab.url {
                log.info("Checking tabURL: \(tabURL)")
                if url.equals(tabURL, with: options) {
                    if let parent = parent {
                        return tab.parent == parent
                    } else {
                        return true
                    }
                }
            } else if let sessionUrl = tab.sessionData?.currentUrl {  // Match zombie tabs
                log.info("Checking sessionUrl: \(sessionUrl)")

                if url.equals(sessionUrl, with: options)
                    || url.equals(InternalURL.unwrapSessionRestore(url: sessionUrl), with: options)
                {
                    if let parent = parent {
                        return tab.parent == parent || tab.parentUUID == parent.tabUUID
                    } else {
                        return true
                    }
                }
            }

            return false
        }
    }

    func getTabCountForCurrentType() -> Int {
        let isIncognito = isIncognito

        if isIncognito {
            return incognitoTabs.count
        } else {
            return activeNormalTabs.count
        }
    }

    func getTabForUUID(uuid: String) -> Tab? {
        assert(Thread.isMainThread)
        let filterdTabs = tabs.filter { tab -> Bool in
            tab.tabUUID == uuid
        }
        return filterdTabs.first
    }

    // MARK: - Select Tab
    // This function updates the _selectedIndex.
    // Note: it is safe to call this with `tab` and `previous` as the same tab, for use in the case where the index of the tab has changed (such as after deletion).
    func selectTab(_ tab: Tab?, previous: Tab? = nil, notify: Bool) {
        assert(Thread.isMainThread)
        let previous = previous ?? selectedTab

        // Make sure to wipe the private tabs if the user has the pref turned on
        if Defaults[.closeIncognitoTabs], !(tab?.isIncognito ?? false), incognitoTabs.count > 0 {
            removeAllIncognitoTabs()
        }

        selectedTab = tab

        // TODO(darin): This writes to a published variable generating a notification.
        // Are we okay with that happening here?
        incognitoModel.update(isIncognito: tab?.isIncognito ?? isIncognito)

        store.preserveTabs(
            tabs, existingSavedTabs: recentlyClosedTabsFlattened,
            selectedTab: selectedTab, for: scene)

        assert(tab === selectedTab, "Expected tab is selected")

        guard let selectedTab = selectedTab else {
            return
        }

        selectedTab.lastExecutedTime = Date.nowMilliseconds()
        selectedTab.applyTheme()

        if selectedTab.shouldPerformHeavyUpdatesUponSelect {
            // Don't need to send WebView notifications if they will be sent below.
            updateWebViewForSelectedTab(notify: !notify)

            // Tab data needs to be updated after the lastExecutedTime is modified.
            updateAllTabDataAndSendNotifications(notify: notify)
        }

        if notify {
            sendSelectTabNotifications(previous: previous)
            selectedTabWebViewPublisher.send(selectedTab.webView)
        }

        if let tab = tab, tab.isIncognito, let url = tab.url, NeevaConstants.isAppHost(url.host),
            !url.path.starts(with: "/incognito")
        {
            tab.webView?.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                if cookies.first(where: {
                    NeevaConstants.isAppHost($0.domain) && $0.name == "httpd~incognito"
                        && $0.isSecure
                }) != nil {
                    return
                }

                StartIncognitoMutation(url: url).perform { result in
                    guard
                        case .success(let data) = result,
                        let url = URL(string: data.startIncognito)
                    else { return }
                    let configuration = URLSessionConfiguration.ephemeral
                    makeURLSession(userAgent: UserAgent.getUserAgent(), configuration: .ephemeral)
                        .dataTask(with: url) { (data, response, error) in
                            print(configuration.httpCookieStorage?.cookies ?? [])
                        }
                }
            }
        }
    }

    func updateWebViewForSelectedTab(notify: Bool) {
        selectedTab?.createWebViewOrReloadIfNeeded()

        if notify {
            selectedTabWebViewPublisher.send(selectedTab?.webView)
        }
    }

    func updateSelectedTabDataPostAnimation() {
        selectedTab?.shouldPerformHeavyUpdatesUponSelect = true

        // Tab data needs to be updated after the lastExecutedTime is modified.
        updateAllTabDataAndSendNotifications(notify: true)
        updateWebViewForSelectedTab(notify: true)
    }

    // Called by other classes to signal that they are entering/exiting private mode
    // This is called by TabTrayVC when the private mode button is pressed and BEFORE we've switched to the new mode
    // we only want to remove all private tabs when leaving PBM and not when entering.
    func willSwitchTabMode(leavingPBM: Bool) {
        // Clear every time entering/exiting this mode.
        Tab.ChangeUserAgent.privateModeHostList = Set<String>()

        if Defaults[.closeIncognitoTabs] && leavingPBM {
            removeAllIncognitoTabs()
        }
    }

    func flagAllTabsToReload() {
        for tab in tabs {
            if tab == selectedTab {
                tab.reload()
            } else if tab.webView != nil {
                tab.needsReloadUponSelect = true
            }
        }
    }

    // MARK: - Incognito
    // TODO(darin): Refactor these methods to set incognito mode. These should probably
    // move to `BrowserModel` and `TabManager` should just observe `IncognitoModel`.
    func setIncognitoMode(to isIncognito: Bool) {
        self.incognitoModel.update(isIncognito: isIncognito)
    }

    func toggleIncognitoMode(
        fromTabTray: Bool = true, clearSelectedTab: Bool = true, openLazyTab: Bool = true,
        selectNewTab: Bool = false
    ) {
        let bvc = SceneDelegate.getBVC(with: scene)

        // set to nil while inconito changes
        if clearSelectedTab {
            selectedTab = nil
        }

        incognitoModel.toggle()

        if selectNewTab {
            if let mostRecentTab = mostRecentTab(inTabs: isIncognito ? incognitoTabs : normalTabs) {
                selectTab(mostRecentTab, notify: true)
            } else if isIncognito && openLazyTab {  // no empty tab tray in incognito
                bvc.openLazyTab(openedFrom: fromTabTray ? .tabTray : .openTab(selectedTab))
            } else {
                let placeholderTab = Tab(
                    bvc: bvc, configuration: configuration, isIncognito: isIncognito)

                // Creates a placeholder Tab to make sure incognito is switched in the Top Bar
                select(placeholderTab)
            }
        }
    }

    func switchIncognitoMode(
        incognito: Bool, fromTabTray: Bool = true, clearSelectedTab: Bool = false,
        openLazyTab: Bool = true
    ) {
        if isIncognito != incognito {
            toggleIncognitoMode(
                fromTabTray: fromTabTray, clearSelectedTab: clearSelectedTab,
                openLazyTab: openLazyTab)
        }
    }

    // Select the most recently visited tab, IFF it is also the parent tab of the closed tab.
    func selectParentTab(afterRemoving tab: Tab) -> Bool {
        let viableTabs = (tab.isIncognito ? incognitoTabs : normalTabs).filter { $0 != tab }
        guard let parentTab = tab.parent, parentTab != tab, !viableTabs.isEmpty,
            viableTabs.contains(parentTab)
        else { return false }

        let parentTabIsMostRecentUsed = mostRecentTab(inTabs: viableTabs) == parentTab
        if parentTabIsMostRecentUsed, parentTab.lastExecutedTime != nil {
            selectTab(parentTab, previous: tab, notify: true)
            return true
        }

        return false
    }

    @objc func prefsDidChange() {
        DispatchQueue.main.async {
            let allowPopups = !Defaults[.blockPopups]
            // Each tab may have its own configuration, so we should tell each of them in turn.
            for tab in self.tabs {
                tab.webView?.configuration.preferences.javaScriptCanOpenWindowsAutomatically =
                    allowPopups
            }
            // The default tab configurations also need to change.
            self.configuration.preferences.javaScriptCanOpenWindowsAutomatically = allowPopups
            self.incognitoConfiguration.preferences.javaScriptCanOpenWindowsAutomatically =
                allowPopups
        }
    }

    func addPopupForParentTab(
        bvc: BrowserViewController, parentTab: Tab, configuration: WKWebViewConfiguration
    ) -> Tab {
        let popup = Tab(bvc: bvc, configuration: configuration, isIncognito: parentTab.isIncognito)
        configureTab(
            popup, request: nil, afterTab: parentTab, flushToDisk: true, zombie: false,
            isPopup: true, notify: true)

        // Wait momentarily before selecting the new tab, otherwise the parent tab
        // may be unable to set `window.location` on the popup immediately after
        // calling `window.open("")`.
        DispatchQueue.main.asyncAfter(deadline: .now() + delaySelectingNewPopupTab) {
            self.selectTab(popup, notify: true)
        }

        // if we open from SRP, carry over the query
        if let parentURL = parentTab.url,
            NeevaConstants.isNeevaSearchResultPage(parentURL),
            let parentQuery = parentTab.queryForNavigation.findQueryForNavigation(with: parentURL)
        {
            var copiedQuery = parentQuery
            copiedQuery.location = .SRP
            popup.queryForNavigation.currentQuery = copiedQuery
        }

        return popup
    }

    func resetProcessPool() {
        assert(Thread.isMainThread)
        configuration.processPool = WKProcessPool()
    }

    func sendSelectTabNotifications(previous: Tab? = nil) {
        selectedTabPublisher.send(selectedTab)

        if selectedTab?.shouldPerformHeavyUpdatesUponSelect ?? true {
            updateWebViewForSelectedTab(notify: true)
        }

        if let tab = previous {
            TabEvent.post(.didLoseFocus, for: tab)
        }

        if let tab = selectedTab {
            TabEvent.post(.didGainFocus, for: tab)
        }
    }

    func rearrangeTabs(fromIndex: Int, toIndex: Int, notify: Bool) {
        let toRootUUID = tabs[toIndex].rootUUID
        if getTabGroup(for: toRootUUID) != nil {
            // If the Tab is being dropped in a TabGroup, change it's,
            // rootUUID so it joins the TabGroup.
            tabs[fromIndex].rootUUID = toRootUUID
        } else {
            // Tab was dragged out of a TabGroup, reset it's rootUUID.
            tabs[fromIndex].rootUUID = UUID().uuidString
        }

        tabs.rearrange(from: fromIndex, to: toIndex)

        if notify {
            updateAllTabDataAndSendNotifications(notify: true)
        }

        preserveTabs()
    }

    func updateActiveTabsAndSendNotifications(notify: Bool) {
        activeTabs =
            incognitoTabs
            + normalTabs.filter {
                return !$0.isArchived
            }

        if notify {
            tabsUpdatedPublisher.send()
        }
    }

    internal func updateAllTabDataAndSendNotifications(notify: Bool) {
        updateActiveTabsAndSendNotifications(notify: false)

        archivedTabs = normalTabs.filter {
            return $0.isArchived
        }

        activeTabGroups = getAll()
            .reduce(into: [String: [Tab]]()) { dict, tab in
                if !tab.isArchived {
                    dict[tab.rootUUID, default: []].append(tab)
                }
            }.filter { $0.value.count > 1 }.reduce(into: [String: TabGroup]()) { dict, element in
                dict[element.key] = TabGroup(children: element.value, id: element.key)
            }

        // In archivedTabsPanelView, there are special UI treatments for a child tab,
        // even if it's the only arcvhied tab in a group. Those tabs won't be filtered
        // out (see activeTabGroups for comparison).
        archivedTabGroups = getAll()
            .reduce(into: [String: [Tab]]()) { dict, tab in
                if tabGroupDict[tab.rootUUID] != nil && tab.isArchived {
                    dict[tab.rootUUID, default: []].append(tab)
                }
            }.reduce(into: [String: TabGroup]()) { dict, element in
                dict[element.key] = TabGroup(children: element.value, id: element.key)
            }

        cleanUpTabGroupNames()
        if notify {
            tabsUpdatedPublisher.send()
        }
    }

    func toggleTabPinnedState(_ tab: Tab) {
        tab.pinnedTime =
            (tab.isPinned ? nil : Date().timeIntervalSinceReferenceDate)
        tab.isPinned.toggle()
        tabsUpdatedPublisher.send()
    }

    // Tab Group related functions
    func removeTabFromTabGroup(_ tab: Tab) {
        tab.rootUUID = UUID().uuidString
        updateAllTabDataAndSendNotifications(notify: true)
    }

    func getTabGroup(for rootUUID: String) -> TabGroup? {
        return activeTabGroups[rootUUID]
    }

    func getTabGroup(for tab: Tab) -> TabGroup? {
        return activeTabGroups[tab.rootUUID]
    }

    func closeTabGroup(_ item: TabGroup) {
        removeTabs(item.children)
    }

    func closeTabGroup(_ item: TabGroup, showToast: Bool) {
        removeTabs(item.children, showToast: showToast)
    }

    func getMostRecentChild(_ item: TabGroup) -> Tab? {
        return item.children.max(by: { lhs, rhs in
            lhs.lastExecutedTime ?? 0 < rhs.lastExecutedTime ?? 0
        })
    }

    func cleanUpTabGroupNames() {
        // The merged set of tab groups is still needed here to avoid displaying different
        // titles for the same tab group. Either subset(active/archive) of a tab group will
        // reference the same dictionary and show the same title.
        let tabGroups = getAll()
            .reduce(into: [String: [Tab]]()) { dict, tab in
                dict[tab.rootUUID, default: []].append(tab)
            }.filter { $0.value.count > 1 }.reduce(into: [String: TabGroup]()) { dict, element in
                dict[element.key] = TabGroup(children: element.value, id: element.key)
            }

        // Write newly created tab group names into dictionary
        tabGroups.forEach { group in
            let id = group.key
            if tabGroupDict[id] == nil {
                tabGroupDict[id] = group.value.displayTitle
            }
        }

        // Garbage collect tab group names for tab groups that don't exist anymore
        var temp = [String: String]()
        tabGroups.forEach { group in
            temp[group.key] = group.value.displayTitle
        }
        tabGroupDict = temp
    }

    public static func makeWebViewConfig(isIncognito: Bool) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.dataDetectorTypes = [.phoneNumber]
        configuration.processPool = WKProcessPool()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = !Defaults[.blockPopups]
        // We do this to go against the configuration of the <meta name="viewport">
        // tag to behave the same way as Safari :-(
        configuration.ignoresViewportScaleLimits = true
        if isIncognito {
            configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        }
        configuration.setURLSchemeHandler(InternalSchemeHandler(), forURLScheme: InternalURL.scheme)

        return configuration
    }

    // MARK: - AddTab
    @discardableResult func addTabsForURLs(
        _ urls: [URL], zombie: Bool = true, shouldSelectTab: Bool = true, incognito: Bool = false,
        rootUUID: String? = nil
    ) -> [Tab] {
        assert(Thread.isMainThread)

        if urls.isEmpty {
            return []
        }

        var newTabs: [Tab] = []
        for url in urls {
            newTabs.append(
                self.addTab(
                    URLRequest(url: url), flushToDisk: false, zombie: zombie,
                    isIncognito: incognito, notify: false))
        }

        if let rootUUID = rootUUID {
            for tab in newTabs {
                tab.rootUUID = rootUUID
            }
        }

        self.updateAllTabDataAndSendNotifications(notify: false)

        // Select the most recent.
        if shouldSelectTab {
            selectTab(newTabs.last, notify: true)
        }

        // Okay now notify that we bulk-loaded so we can adjust counts and animate changes.
        tabsUpdatedPublisher.send()

        // Flush.
        storeChanges()

        return newTabs
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
        configuration: WKWebViewConfiguration? = nil,
        atIndex: Int? = nil,
        afterTab parent: Tab? = nil,
        keepInParentTabGroup: Bool = true,
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
            tab,
            request: request,
            webView: webView,
            atIndex: atIndex,
            afterTab: parent,
            keepInParentTabGroup: keepInParentTabGroup,
            flushToDisk: flushToDisk,
            zombie: zombie,
            query: query,
            suggestedQuery: suggestedQuery,
            visitType: visitType,
            notify: notify
        )

        return tab
    }

    func configureTab(
        _ tab: Tab, request: URLRequest?, webView: WKWebView? = nil, atIndex: Int? = nil,
        afterTab parent: Tab? = nil, keepInParentTabGroup: Bool = true,
        flushToDisk: Bool, zombie: Bool, isPopup: Bool = false,
        query: String? = nil, suggestedQuery: String? = nil,
        queryLocation: QueryForNavigation.Query.Location = .suggestion,
        visitType: VisitType? = nil, notify: Bool
    ) {
        assert(Thread.isMainThread)

        // If network is not available webView(_:didCommit:) is not going to be called
        // We should set request url in order to show url in url bar even no network
        tab.setURL(request?.url)

        insertTab(
            tab,
            atIndex: atIndex,
            parent: parent,
            keepInParentTabGroup: keepInParentTabGroup,
            notify: notify
        )

        if let webView = webView {
            tab.restore(webView)
        } else if !zombie {
            tab.createWebview()
        }

        tab.navigationDelegate = self.navDelegate

        if let query = query {
            tab.queryForNavigation.currentQuery = .init(
                typed: query,
                suggested: suggestedQuery,
                location: queryLocation
            )
        }

        if let request = request {
            if let nav = tab.loadRequest(request), let visitType = visitType {
                tab.browserViewController?.recordNavigationInTab(
                    navigation: nav, visitType: visitType)
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

    private func insertTab(
        _ tab: Tab, atIndex: Int? = nil, parent: Tab? = nil, keepInParentTabGroup: Bool = true,
        notify: Bool
    ) {
        if let atIndex = atIndex, atIndex <= tabs.count {
            tabs.insert(tab, at: atIndex)
        } else {
            var insertIndex: Int? = nil

            // Add tab to be root of a tab group if it follows the rule for the nytimes case.
            // See TabGroupTests.swift for example.
            for possibleChildTab in isIncognito ? incognitoTabs : normalTabs {
                if addTabToTabGroupIfNeeded(newTab: tab, possibleChildTab: possibleChildTab) {
                    guard let childTabIndex = tabs.firstIndex(of: possibleChildTab) else {
                        continue
                    }

                    // Insert the tab where the child tab is so it appears
                    // before it in the Tab Group.
                    insertIndex = childTabIndex
                    break
                }
            }

            if let insertIndex = insertIndex {
                tabs.insert(tab, at: insertIndex)
            } else {
                // If the tab wasn't made a parent of a tab group, move
                // it next to its parent if it has one.
                if let parent = parent, var insertIndex = tabs.firstIndex(of: parent) {
                    insertIndex += 1
                    while insertIndex < tabs.count && tabs[insertIndex].isDescendentOf(parent) {
                        insertIndex += 1
                    }

                    if keepInParentTabGroup {
                        tab.rootUUID = parent.rootUUID
                    }

                    tabs.insert(tab, at: insertIndex)
                } else {
                    // Else just add it to the end of the tabs.
                    tabs.append(tab)
                }
            }

            if let parent = parent {
                tab.parent = parent
                tab.parentUUID = parent.tabUUID
            }
        }

        if notify {
            updateAllTabDataAndSendNotifications(notify: notify)
        }
    }

    func duplicateTab(_ tab: Tab, incognito: Bool) {
        guard let url = tab.url else { return }
        let newTab = addTab(
            URLRequest(url: url), afterTab: tab, isIncognito: incognito)
        selectTab(newTab, notify: true)
    }

    // MARK: Tab Groups
    /// Checks if the new tab URL matches the origin URL for the tab and if so,
    /// then the two tabs should be in a Tab Group together.
    @discardableResult func addTabToTabGroupIfNeeded(
        newTab: Tab, possibleChildTab: Tab
    ) -> Bool {
        guard
            let childTabInitialURL = possibleChildTab.initialURL,
            let newTabURL = newTab.url
        else {
            return false
        }

        let options: [URL.EqualsOption] = [
            .normalizeHost, .ignoreFragment, .ignoreLastSlash, .ignoreScheme,
        ]
        let shouldCreateTabGroup = childTabInitialURL.equals(newTabURL, with: options)

        /// TODO: To make this more effecient, we should refactor `TabGroupManager`
        /// to be apart of `TabManager`. That we can quickly check if the ChildTab is in a Tab Group.
        /// See #3088 + #3098 for more info.
        let childTabIsInTabGroup: Bool = {
            let tabs = tabs.filter { $0 != possibleChildTab }
            for tab in tabs where tab.rootUUID == possibleChildTab.rootUUID {
                return true
            }

            return false
        }()

        if shouldCreateTabGroup {
            if !childTabIsInTabGroup {
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

    // MARK: Restore Tabs
    @discardableResult func restoreSavedTabs(
        _ savedTabs: [SavedTab], isIncognito: Bool = false, shouldSelectTab: Bool = true,
        overrideSelectedTab: Bool = false
    ) -> Tab? {
        // makes sure at least one tab is selected
        // if no tab selected, select the last one (most recently closed)
        var selectedSavedTab: Tab?
        var restoredTabs = [Tab]()
        restoredTabs.reserveCapacity(savedTabs.count)

        for index in savedTabs.indices {
            let savedTab = savedTabs[index]
            let urlRequest: URLRequest? = savedTab.url != nil ? URLRequest(url: savedTab.url!) : nil

            var tab: Tab
            if let tabIndex = savedTab.tabIndex {
                tab = addTab(
                    urlRequest, atIndex: tabIndex, flushToDisk: false, zombie: true,
                    isIncognito: isIncognito, notify: false)
            } else {
                tab = addTab(
                    urlRequest, afterTab: getTabForUUID(uuid: savedTab.parentUUID ?? ""),
                    flushToDisk: false, zombie: true, isIncognito: isIncognito, notify: false)
            }

            savedTab.configureTab(tab, imageStore: store.imageStore)

            restoredTabs.append(tab)

            if savedTab.isSelected {
                selectedSavedTab = tab
            } else if index == savedTabs.count - 1 && selectedSavedTab == nil {
                selectedSavedTab = tab
            }
        }

        resolveParentRef(for: restoredTabs, restrictToActiveTabs: true)

        // Prevents a sticky tab tray
        SceneDelegate.getBVC(with: scene).browserModel.cardTransitionModel.update(to: .hidden)

        if let selectedSavedTab = selectedSavedTab, shouldSelectTab,
            selectedTab == nil || overrideSelectedTab
        {
            self.selectTab(selectedSavedTab, notify: true)
        }

        for savedTab in savedTabs {
            // Find the group that contains the SavedTab.
            guard let groupIndex = recentlyClosedTabs.firstIndex(where: { $0.contains(savedTab) })
            else {
                continue
            }

            // Remove the SavedTab from the group.
            var group = recentlyClosedTabs[groupIndex]
            group.removeAll { $0 == savedTab }

            // Reinsert or delete the group
            if group.count > 0 {
                recentlyClosedTabs[groupIndex] = group
            } else {
                recentlyClosedTabs.remove(at: groupIndex)
            }
        }

        closedTabsToShowToastFor.removeAll { savedTabs.contains($0) }
        updateAllTabDataAndSendNotifications(notify: true)

        return selectedSavedTab
    }

    func restoreAllClosedTabs() {
        restoreSavedTabs(Array(recentlyClosedTabs.joined()))
    }

    func resolveParentRef(for restoredTabs: [Tab], restrictToActiveTabs: Bool = false) {
        let tabs = restrictToActiveTabs ? self.activeTabs : self.tabs
        let uuidMapping = [String: Tab](
            uniqueKeysWithValues: zip(tabs.map { $0.tabUUID }, tabs)
        )

        restoredTabs.forEach { tab in
            guard let parentUUID = tab.parentUUID,
                UUID(uuidString: parentUUID) != nil
            else {
                return
            }
            tab.parent = uuidMapping[parentUUID]
        }
    }

    // MARK: - CloseTabs
    func removeTab(_ tab: Tab?, showToast: Bool = false, updateSelectedTab: Bool = true) {
        guard let tab = tab else {
            return
        }

        // The index of the removed tab w.r.s to the normalTabs/incognitoTabs is
        // calculated in advance, and later used for finding rightOrLeftTab. In time-based
        // switcher, the normalTabs get filtered to make sure we only select tab in
        // today section.
        let normalTabsToday = normalTabs.filter {
            $0.isPinnedTodayOrWasLastExecuted(.today)
        }

        let index =
            tab.isIncognito
            ? incognitoTabs.firstIndex(where: { $0 == tab })
            : normalTabsToday.firstIndex(where: { $0 == tab })

        addTabsToRecentlyClosed([tab], showToast: showToast)
        removeTab(tab, flushToDisk: true, notify: true)

        if (selectedTab?.isIncognito ?? false) == tab.isIncognito, updateSelectedTab {
            updateSelectedTabAfterRemovalOf(tab, deletedIndex: index, notify: true)
        }
    }

    func removeTabs(
        _ tabsToBeRemoved: [Tab], showToast: Bool = true,
        updateSelectedTab: Bool = true, dontAddToRecentlyClosed: Bool = false, notify: Bool = true
    ) {
        guard tabsToBeRemoved.count > 0 else {
            return
        }

        if !dontAddToRecentlyClosed {
            addTabsToRecentlyClosed(tabsToBeRemoved, showToast: showToast)
        }

        let previous = selectedTab
        let lastTab = tabsToBeRemoved[tabsToBeRemoved.count - 1]
        let lastTabIndex = tabs.firstIndex(of: lastTab)
        let tabsToKeep = self.tabs.filter { !tabsToBeRemoved.contains($0) }
        self.tabs = tabsToKeep
        if let lastTabIndex = lastTabIndex, updateSelectedTab {
            updateSelectedTabAfterRemovalOf(lastTab, deletedIndex: lastTabIndex, notify: false)
        }

        tabsToBeRemoved.forEach { tab in
            removeTab(tab, flushToDisk: false, notify: false)
        }

        if notify {
            updateAllTabDataAndSendNotifications(notify: true)
            sendSelectTabNotifications(previous: previous)
        } else {
            updateAllTabDataAndSendNotifications(notify: false)
        }

        storeChanges()
    }

    /// Removes the tab from TabManager, alerts delegates, and stores data.
    /// - Parameter notify: if set to true, will call the delegate after the tab
    ///   is removed.
    private func removeTab(_ tab: Tab, flushToDisk: Bool, notify: Bool) {
        guard let removalIndex = tabs.firstIndex(where: { $0 === tab }) else {
            log.error("Could not find index of tab to remove, tab count: \(count)")
            return
        }

        tabs.remove(at: removalIndex)
        tab.closeWebView()

        tabs.forEach {
            if $0.parent == tab {
                $0.parent = nil
            }
        }

        if tab.isIncognito && incognitoTabs.count < 1 {
            incognitoConfiguration = TabManager.makeWebViewConfig(isIncognito: true)
        }

        if notify {
            TabEvent.post(.didClose, for: tab)
            updateAllTabDataAndSendNotifications(notify: notify)
        }

        if flushToDisk {
            storeChanges()
        }
    }

    private func updateSelectedTabAfterRemovalOf(
        _ tab: Tab, deletedIndex: Int?, notify: Bool
    ) {
        let closedLastNormalTab = !tab.isIncognito && normalTabs.isEmpty
        let closedLastIncognitoTab = tab.isIncognito && incognitoTabs.isEmpty
        // In time-based switcher, the normalTabs gets filtered to make sure we only
        // select tab in today section.
        let viableTabs: [Tab] =
            tab.isIncognito
            ? incognitoTabs
            : normalTabs.filter {
                $0.isPinnedTodayOrWasLastExecuted(.today)
            }
        let bvc = SceneDelegate.getBVC(with: scene)

        if let selectedTab = selectedTab, viableTabs.contains(selectedTab) {
            // The selectedTab still exists, no need to find another tab to select.
            return
        }

        if closedLastNormalTab || closedLastIncognitoTab
            || !viableTabs.contains(where: { $0.isPinnedTodayOrWasLastExecuted(.today) })
        {
            DispatchQueue.main.async {
                self.selectTab(nil, notify: notify)
                bvc.showTabTray()
            }
        } else if let selectedTab = selectedTab, let deletedIndex = deletedIndex {
            if !selectParentTab(afterRemoving: selectedTab) {
                if let rightOrLeftTab = viableTabs[safe: deletedIndex]
                    ?? viableTabs[safe: deletedIndex - 1]
                {
                    selectTab(rightOrLeftTab, previous: selectedTab, notify: notify)
                } else {
                    selectTab(
                        mostRecentTab(inTabs: viableTabs) ?? viableTabs.last, previous: selectedTab,
                        notify: notify)
                }
            }
        } else {
            selectTab(nil, notify: false)
            SceneDelegate.getBVC(with: scene).browserModel.showGridWithNoAnimation()
        }
    }

    // MARK: Remove All Tabs
    func removeAllTabs() {
        removeTabs(tabs, showToast: false)
    }

    func removeAllIncognitoTabs() {
        removeTabs(incognitoTabs, updateSelectedTab: true)
        incognitoConfiguration = TabManager.makeWebViewConfig(isIncognito: true)
    }

    // MARK: Recently Closed Tabs
    func getRecentlyClosedTabForURL(_ url: URL) -> SavedTab? {
        assert(Thread.isMainThread)
        return recentlyClosedTabs.joined().filter({ $0.url == url }).first
    }

    func addTabsToRecentlyClosed(_ tabs: [Tab], showToast: Bool) {
        // Avoid remembering incognito tabs.
        let tabs = tabs.filter { !$0.isIncognito }
        if tabs.isEmpty {
            return
        }

        let savedTabs = tabs.map {
            $0.saveSessionDataAndCreateSavedTab(
                isSelected: selectedTab === $0, tabIndex: self.tabs.firstIndex(of: $0))
        }
        recentlyClosedTabs.insert(savedTabs, at: 0)

        if showToast {
            closedTabsToShowToastFor.append(contentsOf: savedTabs)

            timerToTabsToast?.invalidate()
            timerToTabsToast = Timer.scheduledTimer(
                withTimeInterval: toastGroupTimerInterval, repeats: false,
                block: { _ in
                    ToastDefaults().showToastForClosedTabs(
                        self.closedTabsToShowToastFor, tabManager: self)
                    self.closedTabsToShowToastFor.removeAll()
                })
        }
    }

    // MARK: Zombie Tabs
    /// Turns all but the newest x Tabs into Zombie Tabs.
    func makeTabsIntoZombies(tabsToKeepAlive: Int = 10) {
        // Filter tabs for each Scene
        let tabs = tabs.sorted {
            $0.lastExecutedTime ?? Timestamp() > $1.lastExecutedTime ?? Timestamp()
        }

        tabs.enumerated().forEach { index, tab in
            if tab != selectedTab, index >= tabsToKeepAlive {
                tab.closeWebView()
            }
        }
    }

    /// Used when the user logs out. Clears any Neeva tabs so they are logged out there too.
    func clearNeevaTabs() {
        let neevaTabs = tabs.filter { $0.url?.isNeevaURL() ?? false }
        neevaTabs.forEach { tab in
            if tab == selectedTab {
                tab.reload()
            } else {
                tab.closeWebView()
            }

            // Clear the tab's screenshot by setting it to nil.
            // Will be erased from memory when `storeChanges` is called.
            tab.setScreenshot(nil)
        }
    }

    // MARK: Blank Tabs
    /// Removes any tabs with the location `about:blank`. Seen when clicking web links that open native apps.
    func removeBlankTabs() {
        removeTabs(tabs.filter { $0.url == URL.aboutBlank }, showToast: false)
    }

    // MARK: - CreateOrSwitchToTab
    enum CreateOrSwitchToTabResult {
        case createdNewTab
        case switchedToExistingTab
    }

    @discardableResult func createOrSwitchToTab(
        for url: URL,
        query: String? = nil, suggestedQuery: String? = nil,
        visitType: VisitType? = nil,
        from parentTab: Tab? = nil,
        keepInParentTabGroup: Bool = true
    )
        -> CreateOrSwitchToTabResult
    {
        if let tab = selectedTab {
            ScreenshotHelper(controller: SceneDelegate.getBVC(with: scene)).takeScreenshot(tab)
        }

        if let existingTab = getTabFor(url, with: keepInParentTabGroup ? parentTab : nil) {
            selectTab(existingTab, notify: true)
            existingTab.browserViewController?
                .postLocationChangeNotificationForTab(existingTab, visitType: visitType)

            return .switchedToExistingTab
        } else {
            let newTab = addTab(
                URLRequest(url: url),
                afterTab: parentTab,
                keepInParentTabGroup: keepInParentTabGroup,
                flushToDisk: true,
                zombie: false,
                isIncognito: isIncognito,
                query: query,
                suggestedQuery: suggestedQuery,
                visitType: visitType
            )
            selectTab(newTab, notify: true)

            return .createdNewTab
        }
    }

    @discardableResult func createOrSwitchToTabForSpace(for url: URL, spaceID: String)
        -> CreateOrSwitchToTabResult
    {
        if let tab = selectedTab {
            ScreenshotHelper(controller: SceneDelegate.getBVC(with: scene)).takeScreenshot(tab)
        }

        if let existingTab = getTabFor(url) {
            existingTab.parentSpaceID = spaceID
            existingTab.rootUUID = spaceID
            selectTab(existingTab, notify: true)
            return .switchedToExistingTab
        } else {
            let newTab = addTab(
                URLRequest(url: url), flushToDisk: true, zombie: false, isIncognito: isIncognito)
            newTab.parentSpaceID = spaceID
            newTab.rootUUID = spaceID
            selectTab(newTab, notify: true)
            updateAllTabDataAndSendNotifications(notify: true)
            return .createdNewTab
        }
    }

    // MARK: - TabEventHandler
    func tab(_ tab: Tab, didLoadFavicon favicon: Favicon?, with: Data?) {
        // Write the tabs out again to make sure we preserve the favicon update.
        store.preserveTabs(
            tabs, existingSavedTabs: recentlyClosedTabsFlattened,
            selectedTab: selectedTab, for: scene)
    }

    func tabDidChangeContentBlocking(_ tab: Tab) {
        tab.reload()
    }

    // MARK: - TabStorage
    func preserveTabs() {
        store.preserveTabs(
            tabs, existingSavedTabs: recentlyClosedTabsFlattened,
            selectedTab: selectedTab, for: scene)
    }

    func storeChanges() {
        saveTabs(toProfile: profile, normalTabs)
        store.preserveTabs(
            tabs, existingSavedTabs: recentlyClosedTabsFlattened,
            selectedTab: selectedTab, for: scene)
    }

    private func hasTabsToRestoreAtStartup() -> Bool {
        return store.getStartupTabs(for: scene).count > 0
    }

    private func saveTabs(toProfile profile: Profile, _ tabs: [Tab]) {
        // It is possible that not all tabs have loaded yet, so we filter out tabs with a nil URL.
        let storedTabs: [RemoteTab] = tabs.compactMap(Tab.toRemoteTab)

        // Don't insert into the DB immediately. We tend to contend with more important
        // work like querying for top sites.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            profile.storeTabs(storedTabs)
        }
    }

    /// - Returns: Returns a bool of whether a tab was selected.
    func restoreTabs(_ forced: Bool = false) -> Bool {
        log.info("Restoring tabs")

        guard forced || count == 0, !AppConstants.IsRunningTest, hasTabsToRestoreAtStartup()
        else {
            log.info("Skipping tab restore")
            tabsUpdatedPublisher.send()
            return false
        }

        let tabToSelect = store.restoreStartupTabs(
            for: scene, clearIncognitoTabs: Defaults[.closeIncognitoTabs], tabManager: self)

        if var tabToSelect = tabToSelect {
            if Defaults[.lastSessionPrivate], !tabToSelect.isIncognito {
                tabToSelect = addTab(isIncognito: true, notify: false)
            }

            selectTab(tabToSelect, notify: true)
        }

        updateAllTabDataAndSendNotifications(notify: true)

        return tabToSelect != nil
    }

    // MARK: - TestSupport
    // Helper functions for test cases
    convenience init(
        profile: Profile, imageStore: DiskImageStore?
    ) {
        assert(Thread.isMainThread)

        let scene = SceneDelegate.getCurrentScene(for: nil)
        let incognitoModel = IncognitoModel(isIncognito: false)
        self.init(profile: profile, scene: scene, incognitoModel: incognitoModel)
    }

    func testTabCountOnDisk() -> Int {
        assert(AppConstants.IsRunningTest)
        return store.testTabCountOnDisk(sceneId: SceneDelegate.getCurrentSceneId(for: nil))
    }

    func testCountRestoredTabs() -> Int {
        assert(AppConstants.IsRunningTest)
        return store.getStartupTabs(for: SceneDelegate.getCurrentScene(for: nil)).count
    }

    func testRestoreTabs() {
        assert(AppConstants.IsRunningTest)
        let _ = store.restoreStartupTabs(
            for: SceneDelegate.getCurrentScene(for: nil),
            clearIncognitoTabs: false,
            tabManager: self
        )
    }

    func testClearArchive() {
        assert(AppConstants.IsRunningTest)
        store.clearArchive(for: SceneDelegate.getCurrentScene(for: nil))
    }

    // MARK: - WKNavigationDelegate
    // Note the main frame JSContext (i.e. document, window) is not available yet.
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        // Save stats for the page we are leaving.
        if let tab = self[webView], let blocker = tab.contentBlocker, let url = tab.url {
            blocker.pageStatsCache[url] = blocker.stats
        }
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        // Clear stats for the page we are newly generating.
        if navigationResponse.isForMainFrame, let tab = self[webView],
            let blocker = tab.contentBlocker, let url = navigationResponse.response.url
        {
            blocker.pageStatsCache[url] = nil
        }
        decisionHandler(.allow)
    }

    // The main frame JSContext is available, and DOM parsing has begun.
    // Do not excute JS at this point that requires running prior to DOM parsing.
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard let tab = self[webView] else { return }

        tab.hasContentProcess = true

        if let url = webView.url, let blocker = tab.contentBlocker {
            // Initialize to the cached stats for this page. If the page is being fetched
            // from WebKit's page cache, then this will pick up stats from when that page
            // was previously loaded. If not, then the cached value will be empty.
            blocker.stats = blocker.pageStatsCache[url] ?? TPPageStats()
            if !blocker.isEnabled {
                webView.evaluateJavascriptInDefaultContentWorld(
                    "window.__firefox__.TrackingProtectionStats.setEnabled(false, \(UserScriptManager.appIdToken))"
                )
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let pageZoom = selectedTab?.pageZoom,
            webView.value(forKey: "viewScale") as? CGFloat != pageZoom
        {
            // Trigger the didSet hook
            selectedTab?.pageZoom = pageZoom
        }

        // tab restore uses internal pages, so don't call storeChanges unnecessarily on startup
        if let url = webView.url {
            if let internalUrl = InternalURL(url), internalUrl.isSessionRestore {
                return
            }

            storeChanges()
        }
    }

    /// Called when the WKWebView's content process has gone away. If this happens for the currently selected tab
    /// then we immediately reload it.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard let tab = self[webView] else { return }

        tab.hasContentProcess = false

        if tab == selectedTab {
            tab.consecutiveCrashes += 1

            // Only automatically attempt to reload the crashed
            // tab three times before giving up.
            if tab.consecutiveCrashes < 3 {
                webView.reload()
            } else {
                tab.consecutiveCrashes = 0
            }
        }
    }
}

// WKNavigationDelegates must implement NSObjectProtocol
class TabManagerNavDelegate: NSObject, WKNavigationDelegate {
    fileprivate var delegates = WeakList<WKNavigationDelegate>()

    func insert(_ delegate: WKNavigationDelegate) {
        delegates.insert(delegate)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Logger.network.info("webView.url: \(webView.url ?? "(nil)")")

        for delegate in delegates {
            delegate.webView?(webView, didCommit: navigation)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Logger.network.info("webView.url: \(webView.url ?? "(nil)"), error: \(error)")

        for delegate in delegates {
            delegate.webView?(webView, didFail: navigation, withError: error)
        }
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Logger.network.info("webView.url: \(webView.url ?? "(nil)"), error: \(error)")

        for delegate in delegates {
            delegate.webView?(webView, didFailProvisionalNavigation: navigation, withError: error)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Logger.network.info("webView.url: \(webView.url ?? "(nil)")")

        for delegate in delegates {
            delegate.webView?(webView, didFinish: navigation)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Logger.network.info("webView.url: \(webView.url ?? "(nil)")")

        for delegate in delegates {
            delegate.webViewWebContentProcessDidTerminate?(webView)
        }
    }

    func webView(
        _ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        Logger.network.info("webView.url: \(webView.url ?? "(nil)")")

        let authenticatingDelegates = delegates.filter { wv in
            return wv.responds(to: #selector(webView(_:didReceive:completionHandler:)))
        }

        guard let firstAuthenticatingDelegate = authenticatingDelegates.first else {
            return completionHandler(.performDefaultHandling, nil)
        }

        firstAuthenticatingDelegate.webView?(webView, didReceive: challenge) {
            (disposition, credential) in
            completionHandler(disposition, credential)
        }
    }

    func webView(
        _ webView: WKWebView,
        didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!
    ) {
        Logger.network.info("webView.url: \(webView.url ?? "(nil)")")

        for delegate in delegates {
            delegate.webView?(webView, didReceiveServerRedirectForProvisionalNavigation: navigation)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Logger.network.info("webView.url: \(webView.url ?? "(nil)")")

        for delegate in delegates {
            delegate.webView?(webView, didStartProvisionalNavigation: navigation)
        }
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        Logger.network.info(
            "webView.url: \(webView.url?.absoluteString ?? "(nil)"), request.url: \(navigationAction.request.url?.absoluteString ?? "(nil)"), isMainFrame: \(navigationAction.targetFrame?.isMainFrame.description ?? "(nil)")"
        )

        var res = WKNavigationActionPolicy.allow
        for delegate in delegates {
            delegate.webView?(
                webView, decidePolicyFor: navigationAction,
                decisionHandler: { policy in
                    if policy == .cancel {
                        res = policy
                    }
                })
        }
        decisionHandler(res)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        Logger.network.info(
            "webView.url: \(webView.url ?? "(nil)"), response.url: \(navigationResponse.response.url ?? "(nil)"), isMainFrame: \(navigationResponse.isForMainFrame)"
        )

        var res = WKNavigationResponsePolicy.allow
        for delegate in delegates {
            delegate.webView?(
                webView, decidePolicyFor: navigationResponse,
                decisionHandler: { policy in
                    if policy == .cancel {
                        res = policy
                    }
                })
        }

        decisionHandler(res)
    }
}
