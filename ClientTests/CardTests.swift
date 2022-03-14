// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Defaults
import Shared
import SwiftUI
import ViewInspector
import WalletConnectSwift
import XCTest

@testable import Client

extension CardGrid: Inspectable {}
extension CardsContainer: Inspectable {}
extension TabGridContainer: Inspectable {}
extension CardScrollContainer: Inspectable {}
extension SingleLevelTabCardsView: Inspectable {}
extension GridPicker: Inspectable {}
extension FaviconView: Inspectable {}
extension SwitcherToolbarView: Inspectable {}
extension SpaceCardsView: Inspectable {}
extension FittedCard: Inspectable {}
extension Card: Inspectable {}
extension ThumbnailGroupView: Inspectable {}
extension SpaceContainerView: Inspectable {}

private func assertCast<T>(_ value: Any, to _: T.Type) -> T {
    XCTAssertTrue(value is T)
    return value as! T
}

class CardTests: XCTestCase {
    var profile: TabManagerMockProfile!
    var manager: TabManager!
    var incognitoModel: IncognitoModel!
    var browserModel: BrowserModel!
    var gridModel: GridModel!
    var delegate: MockTabManagerDelegate!
    var groupManager: TabGroupManager!
    var tabCardModel: TabCardModel!
    var tabGroupCardModel: TabGroupCardModel!
    var spaceCardModel: SpaceCardModel!
    @Default(.tabGroupExpanded) private var tabGroupExpanded: Set<String>

    fileprivate let spyDidSelectedTabChange =
        "tabManager(_:didSelectedTabChange:previous:isRestoring:)"
    fileprivate let spyRestoredTabs = "tabManagerDidRestoreTabs(_:)"
    fileprivate let spyAddTab = "tabManager(_:didAddTab:isRestoring:)"

    private struct MockPresenter: WalletConnectPresenter {
        func connectWallet(to wcURL: WCURL) -> Bool {
            return false
        }

        func showModal<Content>(
            style: OverlayStyle, headerButton: OverlayHeaderButton?,
            content: @escaping () -> Content, onDismiss: (() -> Void)?
        ) where Content: View {
            // Do nothing.
        }

        func presentFullScreenModal(content: AnyView, completion: (() -> Void)?) {
            // Do nothing.
        }

        func dismissCurrentOverlay() {
            // Do nothing.
        }
    }

    override func setUp() {
        super.setUp()

        profile = TabManagerMockProfile()
        manager = TabManager(profile: profile, imageStore: nil)
        groupManager = TabGroupManager(tabManager: manager)
        gridModel = GridModel(tabManager: manager, tabGroupManager: groupManager)
        incognitoModel = IncognitoModel(isIncognito: false)
        browserModel = BrowserModel(
            gridModel: gridModel, tabManager: manager, chromeModel: .init(),
            incognitoModel: incognitoModel)
        manager.didRestoreAllTabs = true
        delegate = MockTabManagerDelegate()
        groupManager = TabGroupManager(tabManager: manager)
        tabCardModel = TabCardModel(manager: manager, groupManager: groupManager)
        tabGroupCardModel = TabGroupCardModel(manager: groupManager)

        SpaceStore.shared = .createMock([.stackOverflow, .savedForLater, .shared, .public])
        spaceCardModel = SpaceCardModel()
    }

    override func tearDown() {
        profile._shutdown()
        manager.removeDelegate(delegate)
        manager.removeAllTabs()

        super.tearDown()
    }

    func testTabDetails() throws {
        let tab1 = manager.addTab()

        let _ = MethodSpy(functionName: spyAddTab) { _ in
            XCTAssertEqual(self.tabCardModel.allDetails.count, 1)
            XCTAssertEqual(self.tabCardModel.allDetails.first?.id, tab1.tabUUID)
            XCTAssertFalse(self.tabCardModel.allDetails.first?.isSelected ?? true)
            self.manager.selectTab(tab1)
            XCTAssertTrue(self.tabCardModel.allDetails.first?.isSelected ?? false)

            let tab2 = self.manager.addTab()
            let _ = MethodSpy(functionName: self.spyAddTab) { _ in
                XCTAssertEqual(self.tabCardModel.allDetails.count, 2)
                XCTAssertEqual(self.tabCardModel.allDetails.last?.id, tab2.tabUUID)
                XCTAssertFalse(self.tabCardModel.allDetails.last?.isSelected ?? true)

                XCTAssertTrue(self.groupManager.tabGroups.isEmpty)
                XCTAssertTrue(self.tabGroupCardModel.allDetails.isEmpty)
            }
        }
    }

    func testTabGroupDetails() throws {
        let tab1 = manager.addTab()

        let _ = MethodSpy(functionName: spyAddTab) { _ in
            XCTAssertEqual(self.tabCardModel.allDetails.count, 1)
            XCTAssertEqual(self.tabCardModel.allDetails.first?.id, tab1.tabUUID)
            XCTAssertFalse(self.tabCardModel.allDetails.first?.isSelected ?? true)
            self.manager.selectTab(tab1)
            XCTAssertTrue(self.tabCardModel.allDetails.first?.isSelected ?? false)

            let tab2 = self.manager.addTab(afterTab: tab1)
            let _ = MethodSpy(functionName: self.spyAddTab) { _ in
                XCTAssertEqual(self.tabCardModel.allDetails.count, 2)
                XCTAssertEqual(self.tabCardModel.allDetails.last?.id, tab2.tabUUID)

                XCTAssertTrue(self.tabCardModel.allDetailsWithExclusionList.isEmpty)

                XCTAssertEqual(self.groupManager.tabGroups.count, 1)
                XCTAssertEqual(self.tabGroupCardModel.allDetails.count, 1)
                XCTAssertEqual(self.tabGroupCardModel.allDetails.first?.id, tab1.rootUUID)

                XCTAssertEqual(self.tabGroupCardModel.allDetails.first?.allDetails.count, 2)
                XCTAssertEqual(
                    self.tabGroupCardModel.allDetails.first?.allDetails.first?.id, tab1.tabUUID)
                XCTAssertEqual(
                    self.tabGroupCardModel.allDetails.first?.allDetails.last?.id, tab2.tabUUID)

                let thumbnail = assertCast(
                    self.tabGroupCardModel.allDetails.first!.thumbnail,
                    to: ThumbnailGroupView<TabGroupCardDetails>.self)
                XCTAssertEqual(thumbnail.numItems, 2)

                let tab3 = self.manager.addTab(afterTab: tab1)
                let _ = MethodSpy(functionName: self.spyAddTab) { _ in
                    XCTAssertEqual(self.groupManager.tabGroups.count, 1)
                    XCTAssertEqual(self.tabGroupCardModel.allDetails.count, 1)

                    XCTAssertEqual(self.tabGroupCardModel.allDetails.first?.allDetails.count, 3)
                    XCTAssertEqual(
                        self.tabGroupCardModel.allDetails.first?.allDetails.last?.id, tab3.tabUUID)
                    XCTAssertEqual(thumbnail.numItems, 3)
                }
            }
        }
    }

    func testBuildRowsTwoColumns() throws {
        /*
         The following test constructs the tab in the follwing order:
         [individual tab]
         [child tab (hub site), child tab]
         [individual tab]

         But to save spaces, it should be converted to:
         [individual tab. individual tab]
         [child tab (hub site), child tab]
        */

        let tab1 = manager.addTab()
        let tab2 = manager.addTab()
        let tab3 = manager.addTab(afterTab: tab2)
        let tab4 = manager.addTab()
        // has to call tabGroupCardModel.onDataUpdated() to update representativeTabs
        tabGroupCardModel.onDataUpdated()

        let buildRowsPromotetab4 = tabCardModel.buildRows(
            incognito: false, tabGroupModel: self.tabGroupCardModel, maxCols: 2)

        // Two rows in total
        XCTAssertEqual(buildRowsPromotetab4.count, 2)

        // First row has 2 cells
        XCTAssertEqual(buildRowsPromotetab4[0].cells.count, 2)

        // Second row has 1 cell
        XCTAssertEqual(buildRowsPromotetab4[1].cells.count, 1)

        // Second cell of the first row should be tab 4
        XCTAssertEqual(buildRowsPromotetab4[0].cells[1].id, tab4.id)

        /*
         All tabGroupGridRow should occupy a row by itself. The following test makes sure
         no tab after the last row of an expanded group (which has only one tab) is promoted.

         [individual tab, individual tab]
         [child tab (hub site), child tab]
         [child tab, empty space]
         [individual tab]
         */

        let tab5 = manager.addTab(afterTab: tab3)
        let tab6 = manager.addTab()
        // has to call tabGroupCardModel.onDataUpdated to update representativeTabs
        tabGroupCardModel.onDataUpdated()

        // Make the tab group expanded
        tabGroupExpanded.insert(tab2.rootUUID)

        let buildRowsDontPromotetab6 = tabCardModel.buildRows(
            incognito: false, tabGroupModel: self.tabGroupCardModel, maxCols: 2)

        // There should be four rows in total
        XCTAssertEqual(buildRowsDontPromotetab6.count, 4)

        // Third row should only have 1 tab
        XCTAssertEqual(buildRowsDontPromotetab6[2].numTabsInRow, 1)

        // Fourth row should only have 1 tab, and it will be tab6
        XCTAssertEqual(buildRowsDontPromotetab6[3].cells.count, 1)
        XCTAssertEqual(buildRowsDontPromotetab6[3].cells[0].id, tab6.id)

        tabGroupExpanded.remove(tab2.rootUUID)
    }

    func testBuildRowsThreeColumns() throws {
        /*
         The following test constructs the tab in the follwing order:
         [individual tab]
         [child tab (hub site), child tab, child tab]
         [child tab (hub site), child tab]

         But to save spaces, it should be converted to:
         [individual tab, [child tab (hub site), child tab]]
         [child tab (hub site), child tab, child tab]
        */

        let tab1 = manager.addTab()
        let tab2 = manager.addTab()
        let tab3 = manager.addTab(afterTab: tab2)
        let tab4 = manager.addTab(afterTab: tab3)
        let tab5 = manager.addTab()
        let tab6 = manager.addTab(afterTab: tab5)
        // has to call tabGroupCardModel.onDataUpdated to update representativeTabs
        tabGroupCardModel.onDataUpdated()

        let buildRowsAllSameRow = tabCardModel.buildRows(
            incognito: false, tabGroupModel: self.tabGroupCardModel, maxCols: 3)

        // There should be only two rows
        XCTAssertEqual(buildRowsAllSameRow.count, 2)

        // First row should only have two cells
        XCTAssertEqual(buildRowsAllSameRow[0].cells.count, 2)

        // First cell of the first row should have 1 tab
        XCTAssertEqual(buildRowsAllSameRow[0].cells[0].numTabs, 1)

        // Second cell of the first row should have two tabs
        XCTAssertEqual(buildRowsAllSameRow[0].cells[1].numTabs, 2)

        /*
         All tabGroupGridRow should occupy a row by itself. The following test makes sure
         no tab after the last row of an expanded group (which has only one tab) is promoted.

         [individual tab, [child tab (hub site), child tab]]
         [child tab (hub site), child tab, child tab]
         [child tab, empty space]
         [individual tab]
         */

        let tab7 = manager.addTab(afterTab: tab4)
        let tab8 = manager.addTab()
        // has to call tabGroupCardModel.onDataUpdated to update representativeTabs
        tabGroupCardModel.onDataUpdated()

        // Make the tab group expanded
        tabGroupExpanded.insert(tab2.rootUUID)

        let buildRowsDontPromotetab8 = tabCardModel.buildRows(
            incognito: false, tabGroupModel: self.tabGroupCardModel, maxCols: 3)

        // There should be four rows in total
        XCTAssertEqual(buildRowsDontPromotetab8.count, 4)

        // Third row should only have 1 tab
        XCTAssertEqual(buildRowsDontPromotetab8[2].numTabsInRow, 1)

        // Fourth row should only have 1 tab, and it will be tab8
        XCTAssertEqual(buildRowsDontPromotetab8[3].cells.count, 1)
        XCTAssertEqual(buildRowsDontPromotetab8[3].cells[0].id, tab8.id)

        tabGroupExpanded.remove(tab2.rootUUID)

    }

    func testPinnedTab() throws {
        FeatureFlag.enabledFlags = [FeatureFlag.tabGroupsPinning]

        /*
         Create two tabs. Pin the second tab and test if the
         second tab gets promoted to the front.
         */

        let tab1 = manager.addTab()
        let tab2 = manager.addTab()

        tab2.isPinned = true
        tab2.pinnedTime = Date().timeIntervalSinceReferenceDate
        tabCardModel.onDataUpdated()

        let buildRowsTwoTabs = tabCardModel.buildRows(
            incognito: false, tabGroupModel: self.tabGroupCardModel, maxCols: 2)

        XCTAssertEqual(buildRowsTwoTabs[0].cells.count, 2)
        XCTAssertEqual(buildRowsTwoTabs[0].cells[0].id, tab2.id)
    }

    func testPinnedTabGroup() throws {
        FeatureFlag.enabledFlags = [FeatureFlag.tabGroupsPinning]

        /*
         Create one tab and a tab group with two tabs. Pin the second
         tab in the tab group and check if the tab group gets promoted
         to the first row.
         */

        let tab3 = manager.addTab()
        let tab4 = manager.addTab()
        let tab5 = manager.addTab(afterTab: tab4)

        tab5.isPinned = true
        tab5.pinnedTime = Date().timeIntervalSinceReferenceDate
        tabCardModel.onDataUpdated()
        tabGroupCardModel.onDataUpdated()

        let buildRowsThreeTabs = tabCardModel.buildRows(
            incognito: false, tabGroupModel: self.tabGroupCardModel, maxCols: 2)

        XCTAssertEqual(buildRowsThreeTabs[0].numTabsInRow, 2)
        XCTAssertNotEqual(buildRowsThreeTabs[0].cells[0].id, tab5.id)
    }

    func testPinnedTabsBeforeNonPinnedTabs() throws {
        FeatureFlag.enabledFlags = [FeatureFlag.tabGroupsPinning]

        /*
         Pin one tab and a tab group with two tabs. Make sure a following individual
         tab doesn't get promoted to fill the hole.
         */

        let tab6 = manager.addTab()
        let tab7 = manager.addTab()
        let tab8 = manager.addTab(afterTab: tab7)
        let tab9 = manager.addTab()
        tab6.isPinned = true
        tab6.pinnedTime = Date().timeIntervalSinceReferenceDate
        tab7.isPinned = true
        tab7.pinnedTime = Date().timeIntervalSinceReferenceDate
        tabCardModel.onDataUpdated()
        tabGroupCardModel.onDataUpdated()

        let buildRowsFourTabs = tabCardModel.buildRows(
            incognito: false, tabGroupModel: self.tabGroupCardModel, maxCols: 2)

        XCTAssertEqual(buildRowsFourTabs.count, 3)
        XCTAssertEqual(buildRowsFourTabs[2].cells[0].id, tab9.id)
    }

    func testSpaceDetails() throws {
        XCTAssertEqual(SpaceStore.shared.getAll().count, 4)
        SpaceStore.shared.getAll().first!.contentData = [
            SpaceEntityData(
                id: "id1", url: .aboutBlank, title: nil, snippet: nil,
                thumbnail: SpaceThumbnails.githubThumbnail,
                previewEntity: .webPage),
            SpaceEntityData(
                id: "id2", url: .aboutBlank, title: nil, snippet: nil,
                thumbnail: SpaceThumbnails.stackOverflowThumbnail,
                previewEntity: .webPage),
        ]
        SpaceStore.shared.getAll().last!.contentData = [
            SpaceEntityData(
                id: "id3", url: .aboutBlank, title: nil, snippet: nil,
                thumbnail: SpaceThumbnails.githubThumbnail,
                previewEntity: .webPage)
        ]
        let firstCard = SpaceCardDetails(
            space: SpaceStore.shared.getAll().first!,
            manager: SpaceStore.shared)
        XCTAssertEqual(firstCard.id, Space.stackOverflow.id.id)
        XCTAssertEqual(firstCard.allDetails.count, 2)
        let firstThumbnail = try firstCard.thumbnail.inspect().vStack().view(
            ThumbnailGroupView<SpaceCardDetails>.self, 0
        ).actualView()
        XCTAssertNotNil(firstThumbnail)
        XCTAssertEqual(firstThumbnail.numItems, 2)
        // The model should not update until the SpaceStore refreshes
        XCTAssertEqual(spaceCardModel.allDetails.count, 0)
        // Send a dummy event to simulate a store refresh
        spaceCardModel.onDataUpdated()
        waitForCondition(condition: { spaceCardModel.allDetails.count == 4 })

        let lastCard = spaceCardModel.allDetails.last!
        XCTAssertEqual(lastCard.id, Space.public.id.id)
        XCTAssertEqual(lastCard.allDetails.count, 1)
        let lastThumbnail = try lastCard.thumbnail.inspect().vStack().view(
            ThumbnailGroupView<SpaceCardDetails>.self, 0
        ).actualView()
        XCTAssertNotNil(lastThumbnail)
        XCTAssertEqual(lastThumbnail.numItems, 1)
    }

    func testCardGrid() throws {
        manager.addTab()
        manager.addTab()
        manager.addTab()
        waitForCondition(condition: { manager.tabs.count == 3 })

        let web3Model = Web3Model(server: nil, presenter: MockPresenter(), tabManager: manager)

        let cardGrid = CardGrid()
            .environmentObject(browserModel)
            .environmentObject(browserModel.cardTransitionModel)
            .environmentObject(incognitoModel)
            .environmentObject(tabCardModel).environmentObject(spaceCardModel)
            .environmentObject(tabGroupCardModel).environmentObject(gridModel)
            .environmentObject(web3Model)
            .environmentObject(web3Model.walletDetailsModel)

        let cardContainer = try cardGrid.inspect().find(CardsContainer.self)
        XCTAssertNotNil(cardContainer)
        waitForCondition {
            try cardGrid.inspect().findAll(FaviconView.self).count == 3
        }

        manager.addTab()
        manager.addTab()
        waitForCondition(condition: { manager.tabs.count == 5 })
        XCTAssertEqual(manager.tabs.count, 5)
        waitForCondition {
            try cardGrid.inspect().findAll(FaviconView.self).count == 5
        }
    }

    func testCardGridWithSpaces() throws {
        manager.addTab()
        manager.addTab()
        manager.addTab()
        waitForCondition(condition: { manager.tabs.count == 3 })

        gridModel.switcherState = .spaces
        spaceCardModel.onDataUpdated()
        waitForCondition(condition: { spaceCardModel.allDetails.count == 4 })

        let cardContainer = CardsContainer(
            columns: Array(repeating: GridItem(.fixed(100), spacing: 20), count: 2)
        )
        .environmentObject(browserModel)
        .environmentObject(browserModel.cardTransitionModel)
        .environmentObject(incognitoModel)
        .environmentObject(tabCardModel)
        .environmentObject(spaceCardModel)
        .environmentObject(tabGroupCardModel)
        .environmentObject(gridModel)
        .environmentObject(tabGroupCardModel)

        let spaceCardsView = try cardContainer.inspect().find(SpaceCardsView.self)
        XCTAssertNotNil(spaceCardsView)

        let spaceCards = spaceCardsView.findAll(FittedCard<SpaceCardDetails>.self)
        XCTAssertEqual(spaceCards.count, 4)
    }
}
