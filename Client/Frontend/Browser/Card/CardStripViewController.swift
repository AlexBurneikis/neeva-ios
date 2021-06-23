// Copyright Neeva. All rights reserved.

import Foundation
import SwiftUI

public enum CardStripUX {
    static let BottomPadding: CGFloat = 50
    static let Height = 275
}

class CardStripViewController: UIViewController {
    lazy var cardStripHostingController: UIHostingController<TabsAndSpacesView>? = {
        let host = UIHostingController(
            rootView: TabsAndSpacesView(
                tabModel: self.tabCardModel,
                spaceModel: self.spaceCardModel,
                sitesModel: self.sitesCardModel))
        host.view.backgroundColor = UIColor.clear
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        return host
    }()

    weak var tabManager: TabManager?

    var tabCardModel: TabCardModel
    var spaceCardModel: SpaceCardModel
    var sitesCardModel: SiteCardModel

    init(tabManager: TabManager) {
        self.tabManager = tabManager
        self.tabCardModel = TabCardModel(manager: tabManager)
        self.spaceCardModel = SpaceCardModel()
        self.sitesCardModel = SiteCardModel(urls: [],
                                            profile: BrowserViewController.foregroundBVC().profile)
        super.init(nibName: nil, bundle: nil)
        view.backgroundColor = .clear
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        cardStripHostingController?.view.snp.updateConstraints { make in
            make.edges.equalToSuperview()
        }
        tabCardModel.onViewUpdate = {
            BrowserViewController.foregroundBVC().view.bringSubviewToFront(self.view)
        }
    }

}
