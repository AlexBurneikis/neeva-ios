// Copyright Neeva. All rights reserved.

import Shared
import Storage
import SDWebImage
import Defaults

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var scene: UIScene?

    private var tabManager: TabManager!
    private var tabTrayController: TabTrayControllerV1!
    private var browserViewController: BrowserViewController!
    private var geigerCounter: KMCGeigerCounter?

    // MARK: - Scene state
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        self.scene = scene
        
        guard let scene = (scene as? UIWindowScene) else { return }

        window = .init(windowScene: scene)
        window?.makeKeyAndVisible()

        setupRootViewController(scene)

        if Defaults[.enableGeigerCounter] {
            startGeigerCounter()
        }
    }

    private func setupRootViewController(_ scene: UIScene) {
        let profile = getAppDelegateProfile()

        self.tabManager = TabManager(profile: profile, scene: scene)
        self.browserViewController = BrowserViewController(profile: profile, tabManager: tabManager)
        self.tabTrayController = TabTrayControllerV1(tabManager: tabManager, profile: profile)

        browserViewController.edgesForExtendedLayout = []
        browserViewController.restorationIdentifier = NSStringFromClass(BrowserViewController.self)
        browserViewController.restorationClass = AppDelegate.self

        let navigationController = NavigationController(rootViewController: browserViewController)
        navigationController.delegate = self
        navigationController.edgesForExtendedLayout = UIRectEdge(rawValue: 0)
        window!.rootViewController = navigationController

        browserViewController.tabManager.selectedTab?.reload()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        self.scene = scene
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        tabManager.preserveTabs()
    }

    // MARK: - URL managment
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        // almost always one URL
        guard let url = URLContexts.first?.url, let routerpath = NavigationPath(url: url) else {
            return
        }

        if let _ = Defaults[.appExtensionTelemetryOpenUrl] {
            Defaults[.appExtensionTelemetryOpenUrl] = nil
            var object = TelemetryWrapper.EventObject.url
            if case .text(_) = routerpath {
                object = .searchText
            }

            TelemetryWrapper.recordEvent(category: .appExtensionAction, method: .applicationOpenUrl, object: object)
        }

        DispatchQueue.main.async {
            NavigationPath.handle(nav: routerpath, with: BrowserViewController.foregroundBVC())
        }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        if !continueSiriIntent(continue: userActivity) {
            _ = checkForUniversalURL(continue: userActivity)
        }
    }

    func continueSiriIntent(continue userActivity: NSUserActivity) -> Bool {
        if let intent = userActivity.interaction?.intent as? OpenURLIntent {
            BrowserViewController.foregroundBVC().openURLInNewTab(intent.url)
            return true
        }

        if let intent = userActivity.interaction?.intent as? SearchNeevaIntent,
           let query = intent.text,
           let url = neevaSearchEngine.searchURLForQuery(query) {
            BrowserViewController.foregroundBVC().openURLInNewTab(url)
            return true
        }

        return false
    }

    func checkForUniversalURL(continue userActivity: NSUserActivity) -> Bool {
        // Get URL components from the incoming user activity.
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
            let incomingURL = userActivity.webpageURL else {
            return false
        }

        BrowserViewController.foregroundBVC().openURLInNewTab(incomingURL)

        return true
    }

    // MARK: - Shortcut
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        let handledShortCutItem = QuickActions.sharedInstance.handleShortCutItem(shortcutItem, withBrowserViewController: BrowserViewController.foregroundBVC())
        completionHandler(handledShortCutItem)
    }

    // MARK: - Get data from current scene
    static func getCurrentSceneDelegate() -> SceneDelegate {
        for scene in UIApplication.shared.connectedScenes {
            if scene.activationState == .foregroundActive || UIApplication.shared.connectedScenes.count == 1, let sceneDelegate = ((scene as? UIWindowScene)?.delegate as? SceneDelegate) {
                return sceneDelegate
            }
        }

        fatalError("Scene Delegate doesn't exist or is nil")
    }

    static func getForegroundTabTrayController() -> TabTrayControllerV1? {
        return getCurrentSceneDelegate().tabTrayController
    }

    static func getCurrentScene() -> UIScene {
        if let scene = getCurrentSceneDelegate().scene {
            return scene
        }

        fatalError("Scene doesn't exist or is nil")
    }

    static func getCurrentSceneId() -> String {
        return getCurrentScene().session.persistentIdentifier
    }

    public func getBVC() -> BrowserViewController {
        return browserViewController
    }

    // MARK: - Geiger
    public func startGeigerCounter() {
        if let scene = self.scene as? UIWindowScene {
            geigerCounter = KMCGeigerCounter(windowScene: scene)
        }
    }

    public func stopGeigerCounter() {
        geigerCounter?.disable()
        geigerCounter = nil
    }
}

// MARK: - Root View Controller Animations
extension SceneDelegate: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation, from fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        switch operation {
        case .push:
            return BrowserToTrayAnimator()
        case .pop:
            return TrayToBrowserAnimator()
        default:
            return nil
        }
    }
}
