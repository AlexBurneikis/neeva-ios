// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Combine
import Shared
import SwiftUI
import UIKit

class ToastDefaults: NSObject {
    var toast: ToastView?
    var toastProgressViewModel: ToastProgressViewModel?

    private var requestListener: AnyCancellable?
    // This is used to subscribe to SpaceStore's state
    // in order to properly update the UI
    private var refreshListener: AnyCancellable?

    func showToast(with text: String, toastViewManager: ToastViewManager, checkmark: Bool = false) {
        let toastView = toastViewManager.makeToast(
            text: LocalizedStringKey(text), checkmark: checkmark)
        toast = toastView
    }

    func showToastForClosedTabs(_ savedTabs: [SavedTab], tabManager: TabManager) {
        guard savedTabs.count > 0 else {
            return
        }

        var toastText: LocalizedStringKey = "Tab Closed"
        let keyboardShortcutDescription = {
            AnyView(
                (Text("\(Image(systemName: "shift"))")
                    + Text("\(Image(systemName: "command"))") + Text("T to restore"))
                    .withFont(.bodyXSmall).foregroundColor(.secondaryLabel))
        }

        if savedTabs.count > 0 {
            if savedTabs.count > 1 {
                toastText = "\(savedTabs.count) Tabs Closed"
            }

            let toastContent = ToastViewContent(
                normalContent: ToastStateContent(
                    text: toastText,
                    description: UIDevice.current.useTabletInterface
                        ? keyboardShortcutDescription : nil,
                    buttonText: "restore",
                    buttonAction: {
                        let bvc = SceneDelegate.getBVC(with: tabManager.scene)
                        bvc.tabManager.restoreSavedTabs(savedTabs)
                    },
                    keyboardShortcut: KeyboardShortcut("t", modifiers: [.command, .shift])
                )
            )

            let toastViewManager = SceneDelegate.getBVC(with: tabManager.scene).toastViewManager
            toast = toastViewManager.makeToast(content: toastContent)
        }
    }

    func showToastForPinningTab(pinning: Bool, tabManager: TabManager) {
        let toastText = pinning ? "Tab Pinned" : "Tab Unpinned"

        let toastViewManager = SceneDelegate.getBVC(with: tabManager.scene).toastViewManager
        showToast(with: toastText, toastViewManager: toastViewManager, checkmark: true)
    }

    func showToastForDownload(download: Download, toastViewManager: ToastViewManager) {
        resetProgress()

        toastProgressViewModel?.downloadListener = download.$bytesDownloaded.sink {
            [self] bytesDownloaded in
            guard let bytesExpected = download.totalBytesExpected else {
                toastProgressViewModel?.downloadListener = nil
                toastProgressViewModel?.progress = nil
                return
            }

            withAnimation(.default) {
                toastProgressViewModel?.progress = Double(bytesDownloaded) / Double(bytesExpected)
            }
        }

        download.delegate = self

        let normalContent = ToastStateContent(text: "Downloading", buttonText: "cancel") {
            download.cancel()
        }
        let completedContent = ToastStateContent(text: "Downloaded", buttonText: "open") {
            openDownloadsFolderInFilesApp()
        }
        let failedContent = ToastStateContent(text: "Download Failed")

        let toastContent = ToastViewContent(
            normalContent: normalContent, completedContent: completedContent,
            failedContent: failedContent)

        toast = toastViewManager.makeToast(
            content: toastContent, toastProgressViewModel: toastProgressViewModel,
            autoDismiss: false)
    }

    func showToastForAddToSpaceUI(bvc: BrowserViewController, request: AddToSpaceRequest) {
        toastProgressViewModel = ToastProgressViewModel()
        toastProgressViewModel?.status = .inProgress

        requestListener = request.$state.sink { [weak self] updatedState in
            guard let self = self else { return }

            if updatedState == .failed {
                self.toastProgressViewModel?.status = .failed
            } else {
                self.toastProgressViewModel?.status = .success
                if let spaceID = request.targetSpaceID {
                    SpaceStore.shared.refreshSpace(spaceID: spaceID, url: request.url)
                }
            }
        }

        let spaceName = request.targetSpaceName ?? "## Unknown ##"
        let (toastText, completedText, deleted) = request.textInfo

        let buttonAction = {
            if let spaceID = request.targetSpaceID {
                bvc.browserModel.openSpace(spaceID: spaceID)
            } else {
                bvc.browserModel.showSpaces()
            }
        }

        let failedAction = {
            if deleted {
                request.deleteFromExistingSpace(
                    id: request.targetSpaceID ?? "", name: request.targetSpaceName ?? "")
            } else {
                request.addToExistingSpace(
                    id: request.targetSpaceID ?? "", name: request.targetSpaceName ?? "")
            }

            self.showToastForAddToSpaceUI(bvc: bvc, request: request)
        }

        let normalContent = ToastStateContent(
            text: toastText, buttonText: "open space", buttonAction: buttonAction)
        let completedContent = ToastStateContent(
            text: completedText, buttonText: "open space", buttonAction: buttonAction)
        let failedContent = ToastStateContent(
            text: "Failed to \(deleted ? "delete from" : "save to") \"\(spaceName)\"",
            buttonText: "try again",
            buttonAction: failedAction)
        let toastContent = ToastViewContent(
            normalContent: normalContent, completedContent: completedContent,
            failedContent: failedContent)

        let toastViewManager = bvc.toastViewManager
        toast = toastViewManager.makeToast(
            content: toastContent, toastProgressViewModel: toastProgressViewModel,
            autoDismiss: false)
    }

    func showToastForRemoveFromSpace(
        bvc: BrowserViewController, request: DeleteSpaceItemsRequest,
        undoDeletion: @escaping () -> Void, retryDeletion: @escaping () -> Void
    ) {
        resetProgress()

        requestListener = request.$state.sink { [weak self] updatedState in
            guard let self = self else { return }

            if updatedState == .failure {
                self.toastProgressViewModel?.status = .failed
            } else {
                self.toastProgressViewModel?.status = .success
            }
        }

        let normalContent = ToastStateContent(text: "Removing item from Space")
        let completedContent = ToastStateContent(
            text: "Item removed from Space", buttonText: "undo", buttonAction: undoDeletion)
        let failedContent = ToastStateContent(
            text: "Failed to remove item from Space",
            buttonText: "try again",
            buttonAction: retryDeletion)
        let toastContent = ToastViewContent(
            normalContent: normalContent, completedContent: completedContent,
            failedContent: failedContent)

        let toastViewManager = bvc.toastViewManager
        toast = toastViewManager.makeToast(
            content: toastContent, toastProgressViewModel: toastProgressViewModel,
            autoDismiss: false)
    }

    func showToastForFeedback(request: FeedbackRequest, toastViewManager: ToastViewManager) {
        let normalContent = ToastStateContent(text: "Sent. Thanks for your feedback!")
        let toastContent = ToastViewContent(
            normalContent: normalContent)

        toast = toastViewManager.makeToast(
            content: toastContent,
            toastProgressViewModel: toastProgressViewModel)
    }

    func showToastForSetPreferredProvider(
        request: PreferredProviderRequest, toastViewManager: ToastViewManager
    ) {
        resetProgress()

        requestListener = request.$state.sink { [weak self] updatedState in
            guard let self = self else { return }

            switch updatedState {
            case .inProgress:
                self.toastProgressViewModel?.status = .inProgress
            case .success:
                self.toastProgressViewModel?.status = .success
            case .failed:
                self.toastProgressViewModel?.status = .failed
            }
        }

        let failedAction = {
            request.setPreferredProvider()
            self.showToastForSetPreferredProvider(
                request: request, toastViewManager: toastViewManager)
        }

        let normalContent = ToastStateContent(text: "Saving preference")
        let completedContent = ToastStateContent(text: "Preference saved!", buttonText: "Got it")

        let failedContent = ToastStateContent(
            text: "Failed to save preference",
            buttonText: "try again",
            buttonAction: failedAction)
        let toastContent = ToastViewContent(
            normalContent: normalContent, completedContent: completedContent,
            failedContent: failedContent)

        toast = toastViewManager.makeToast(
            content: toastContent,
            toastProgressViewModel: toastProgressViewModel, autoDismiss: false)
    }

    func showToastForSwitchToTab(_ tab: Tab?, incognito: Bool, tabManager: TabManager) {
        if let tab = tab {
            let bvc = SceneDelegate.getBVC(with: tabManager.scene)
            let toastViewManager = bvc.toastViewManager

            let toastLabelText: LocalizedStringKey =
                incognito
                ? "New Incognito Tab opened"
                : "New Tab opened"

            toast = toastViewManager.makeToast(
                text: toastLabelText,
                buttonText: "Switch",
                buttonAction: {
                    tabManager.selectTab(tab, notify: true)

                    if let presentedViewController = bvc.presentedViewController {
                        presentedViewController.dismiss(animated: true, completion: nil)
                    }
                }
            )
        }
    }

    private func resetProgress() {
        toastProgressViewModel = ToastProgressViewModel()
        toastProgressViewModel?.status = .inProgress
        toastProgressViewModel?.progress = nil
        toastProgressViewModel?.downloadListener = nil
    }
}

extension ToastDefaults: DownloadDelegate {
    func download(_ download: Download, didDownloadBytes bytesDownloaded: Int64) {

    }

    func download(_ download: Download, didFinishDownloadingTo location: URL) {
        toastProgressViewModel?.status = .success
        downloadComplete()
    }

    func download(_ download: Download, didCompleteWithError error: Error?) {
        if error != nil {
            print("Download failed with error:", error as Any)

            toastProgressViewModel?.status = .failed
            downloadComplete()
        }
    }

    func downloadComplete() {
        self.toast = nil
    }
}
