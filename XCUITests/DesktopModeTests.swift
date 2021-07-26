/* This Source Code Form is subject to the terms of the Mozilla Public
 License, v. 2.0. If a copy of the MPL was not distributed with this
 file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import XCTest

// Tests for both platforms
class DesktopModeTestsIpad: IpadOnlyTestCase {
    func testLongPressReload() {
        if skipPlatform { return }
        navigator.openURL(path(forTestPage: "test-user-agent.html"))
        waitUntilPageLoad()
        XCTAssert(app.webViews.staticTexts.matching(identifier: "DESKTOP_UA").count > 0)

        navigator.goto(ReloadLongPressMenu)
        navigator.performAction(Action.RequestMobileSiteViaReloadMenu)
        waitUntilPageLoad()
        XCTAssert(app.webViews.staticTexts.matching(identifier: "MOBILE_UA").count > 0)

        // Covering scenario that when reloading the page should preserve Desktop site
        navigator.performAction(Action.ReloadURL)
        XCTAssert(app.webViews.staticTexts.matching(identifier: "MOBILE_UA").count > 0)

        closeAllTabs()

        // Covering scenario that when closing a tab and re-opening should preserve Mobile mode
        navigator.createNewTab()
        navigator.openURL(path(forTestPage: "test-user-agent.html"))
        waitUntilPageLoad()
        XCTAssert(app.webViews.staticTexts.matching(identifier: "MOBILE_UA").count > 0)
    }
}

class DesktopModeTestsIphone: IphoneOnlyTestCase {
    func testClearPrivateData() {
        if skipPlatform { return }

        navigator.openURL(path(forTestPage: "test-user-agent.html"))
        waitUntilPageLoad()
        XCTAssert(app.webViews.staticTexts.matching(identifier: "MOBILE_UA").count > 0)
        navigator.goto(ShareMenu)
        navigator.goto(RequestDesktopSite)
        waitUntilPageLoad()
        XCTAssert(app.webViews.staticTexts.matching(identifier: "DESKTOP_UA").count > 0)

        // Go to Clear Data
        navigator.nowAt(BrowserTab)
        navigator.performAction(Action.AcceptClearPrivateData)
        navigator.goto(BrowserTab)
        
        // Tab #2
        navigator.nowAt(BrowserTab)
        navigator.performAction(Action.OpenNewTabLongPressTabsButton)
        navigator.openURL(path(forTestPage: "test-user-agent.html"))
        waitUntilPageLoad()
        XCTAssert(app.webViews.staticTexts.matching(identifier: "MOBILE_UA").count > 0)
    }

    func testSameHostInMultipleTabs() {
        if skipPlatform { return }

        navigator.nowAt(NewTabScreen)
        navigator.openURL(path(forTestPage: "test-user-agent.html"))
        waitUntilPageLoad()
        XCTAssert(app.webViews.staticTexts.matching(identifier: "MOBILE_UA").count > 0)
        navigator.goto(ShareMenu)
        navigator.goto(RequestDesktopSite)
        waitUntilPageLoad()
        XCTAssert(app.webViews.staticTexts.matching(identifier: "DESKTOP_UA").count > 0)

        // Tab #2
        navigator.nowAt(BrowserTab)
        navigator.performAction(Action.OpenNewTabLongPressTabsButton)
        navigator.openURL(path(forTestPage: "test-user-agent.html"))
        waitUntilPageLoad()
        XCTAssert(app.webViews.staticTexts.matching(identifier: "DESKTOP_UA").count > 0)
        navigator.goto(ShareMenu)
        navigator.goto(RequestMobileSite)
        waitUntilPageLoad()
        XCTAssert(app.webViews.staticTexts.matching(identifier: "MOBILE_UA").count > 0)

        // Tab #3
        navigator.nowAt(BrowserTab)
        navigator.performAction(Action.OpenNewTabLongPressTabsButton)
        navigator.openURL(path(forTestPage: "test-user-agent.html"))
        waitUntilPageLoad()
        XCTAssert(app.webViews.staticTexts.matching(identifier: "MOBILE_UA").count > 0)
    }
    
    // Smoketest
    /* https://github.com/neevaco/neeva-ios-phoenix/issues/1091
    func testChangeModeInSameTab() {
        if skipPlatform { return }

        navigator.openURL(path(forTestPage: "test-user-agent.html"))
        waitUntilPageLoad()
        XCTAssert(app.webViews.staticTexts.matching(identifier: "MOBILE_UA").count > 0)
        navigator.goto(ShareMenu)
        navigator.goto(RequestDesktopSite)
        waitUntilPageLoad()
        XCTAssert(app.webViews.staticTexts.matching(identifier: "DESKTOP_UA").count > 0)
        
        navigator.nowAt(BrowserTab)
        navigator.goto(ShareMenu)
        // Select Mobile site here, the identifier is the same but the Text is not
        navigator.goto(RequestMobileSite)
        waitUntilPageLoad()
        XCTAssert(app.webViews.staticTexts.matching(identifier: "MOBILE_UA").count > 0)
    }*/

    // Was flaky on bots testing irrelevant changes. Disabling to fix later.
    /*func testPrivateModeOffAlsoRemovesFromNormalMode() {
        if skipPlatform { return }

        navigator.openURL(path(forTestPage: "test-user-agent.html"))
        waitUntilPageLoad()
        XCTAssert(app.webViews.staticTexts.matching(identifier: "MOBILE_UA").count > 0)
        navigator.goto(ShareMenu)
        navigator.goto(RequestDesktopSite) // toggle on
        waitUntilPageLoad()
        XCTAssert(app.webViews.staticTexts.matching(identifier: "DESKTOP_UA").count > 0)

        // is now on in normal mode

        navigator.nowAt(BrowserTab)
        navigator.toggleOn(userState.isPrivate, withAction: Action.TogglePrivateMode)
        navigator.openURL(path(forTestPage: "test-user-agent.html"))
        // Workaround to be sure the snackbar dissapers
        app.buttons["Reload"].tap()
        navigator.goto(ShareMenu)
        navigator.goto(RequestMobileSite) // toggle off
        waitUntilPageLoad()
        XCTAssert(app.webViews.staticTexts.matching(identifier: "MOBILE_UA").count > 0)

        // is now off in private, mode, confirm it is off in normal mode

        navigator.nowAt(BrowserTab)
        navigator.toggleOff(userState.isPrivate, withAction: Action.TogglePrivateMode)
        navigator.openURL(path(forTestPage: "test-user-agent.html"))
        waitUntilPageLoad()
        XCTAssert(app.webViews.staticTexts.matching(identifier: "MOBILE_UA").count > 0)
    }*/

    func testPrivateModeOnHasNoAffectOnNormalMode() {
        if skipPlatform { return }

        navigator.nowAt(NewTabScreen)
        navigator.openURL(path(forTestPage: "test-user-agent.html"))
        waitUntilPageLoad()
        XCTAssert(app.webViews.staticTexts.matching(identifier: "MOBILE_UA").count > 0)

        navigator.toggleOn(userState.isPrivate, withAction: Action.TogglePrivateMode)
        navigator.nowAt(NewTabScreen)

        navigator.openURL(path(forTestPage: "test-user-agent.html"))
        waitUntilPageLoad()
        // Workaround
        app.buttons["Reload"].tap()
        navigator.goto(ShareMenu)
        navigator.goto(RequestDesktopSite)
        waitUntilPageLoad()
        XCTAssert(app.webViews.staticTexts.matching(identifier: "DESKTOP_UA").count > 0)

        navigator.nowAt(BrowserTab)
        navigator.toggleOff(userState.isPrivate, withAction: Action.ToggleRegularMode)
        navigator.openURL(path(forTestPage: "test-user-agent.html"))
        waitUntilPageLoad()
        XCTAssert(app.webViews.staticTexts.matching(identifier: "MOBILE_UA").count > 0)
    }

    /* Disabled: Action to close all tabs does not exist.
    func testLongPressReload() {
        if skipPlatform { return }
        navigator.openURL(path(forTestPage: "test-user-agent.html"))
        waitUntilPageLoad()
        XCTAssert(app.webViews.staticTexts.matching(identifier: "MOBILE_UA").count > 0)

        navigator.goto(ReloadLongPressMenu)
        navigator.performAction(Action.RequestDesktopSiteViaReloadMenu)
        waitUntilPageLoad()
        XCTAssert(app.webViews.staticTexts.matching(identifier: "DESKTOP_UA").count > 0)

        // Covering scenario that when reloading the page should preserve Desktop site
        navigator.performAction(Action.ReloadURL)
        XCTAssert(app.webViews.staticTexts.matching(identifier: "DESKTOP_UA").count > 0)

        navigator.performAction(Action.AcceptRemovingAllTabs)

        // Covering scenario that when closing a tab and re-opening should preserve Desktop mode
        navigator.createNewTab()
        navigator.openURL(path(forTestPage: "test-user-agent.html"))
        waitUntilPageLoad()
        XCTAssert(app.webViews.staticTexts.matching(identifier: "DESKTOP_UA").count > 0)
    }
    */
}
