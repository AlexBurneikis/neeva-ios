//
//  ShareSpaceView.swift
//  
//
//  Created by Jed Fox on 12/22/20.
//

import SwiftUI
import Apollo

struct InviteState {
    var shareType = SpaceACLLevel.comment
    var selected = [ContactSuggestionController.Suggestion]()
    var note = ""
}

struct InvitationSentState {
    let invitationsSent: Int
    let nonNeevanEmails: [String]
}

struct ShareSpaceView: View {
    @StateObject var publicityController: SpacePublicACLController
    @StateObject var suggestionsController = ContactSuggestionController()

    @Environment(\.presentationMode) var presentationMode

    @State var invite = InviteState()
    @State var sendingInvites: Apollo.Cancellable?
    @State var sentInvites: InvitationSentState?

    let space: SpaceController.Space
    let spaceId: String
    let onUpdate: Updater<SpaceController.Space>

    init(
        space: SpaceController.Space,
        id: String,
        onUpdate: @escaping Updater<SpaceController.Space>,
        sendingInvites: Apollo.Cancellable? = nil,
        sentInvites: InvitationSentState? = nil
    ) {
        self.space = space
        self.spaceId = id
        self.onUpdate = onUpdate
        self._sendingInvites = .init(initialValue: sendingInvites)
        self._sentInvites = .init(initialValue: sentInvites)

        self._publicityController = .init(wrappedValue: SpacePublicACLController(id: id, hasPublicACL: space.hasPublicAcl ?? false))
    }

    var body: some View {
        let canEditSettings = space.userAcl?.acl == .owner
        NavigationView {
            if let sendingInvites = sendingInvites {
                VStack {
                    Spacer()
                    HStack { Spacer() }
                    LoadingView("Sharing…")
                    Spacer()
                }
                .navigationBarItems(
                    leading: Button("Cancel") {
                        sendingInvites.cancel()
                        self.sendingInvites = nil
                    }.font(.body)
                )
                .navigationBarTitleDisplayMode(.inline)
                .background(
                    Color(UIColor.systemGroupedBackground)
                        .edgesIgnoringSafeArea(.all)
                )
            } else if let sentInvites = sentInvites {
                VStack {
                    Spacer()
                    HStack { Spacer() }
                    if sentInvites.nonNeevanEmails.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.largeTitle)
                            .imageScale(.large)
                            .foregroundColor(.green)
                            .padding(.bottom)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .imageScale(.large)
                            .foregroundColor(.yellow)
                            .padding(.bottom)
                    }
                    Text("Sent \(sentInvites.invitationsSent) invitation\(sentInvites.invitationsSent == 1 ? "" : "s").")
                        .font(.title).bold()
                    if !sentInvites.nonNeevanEmails.isEmpty {
                        let count = sentInvites.nonNeevanEmails.count
                        VStack(spacing: 30) {
                            Text("We couldn't find Neeva users for \(count) of the addresses you entered.")
                            if publicityController.hasPublicACL {
                                Text("Would you like to send them the public link?")
                                Button(action: {
                                    sendingInvites = ShareSpacePublicLinkMutation(
                                        space: spaceId,
                                        emails: sentInvites.nonNeevanEmails,
                                        note: invite.note
                                    ).perform { result in
                                        sendingInvites = nil
                                        if case .success(let data) = result,
                                           let result = data.shareSpacePublicLink,
                                           let numShared = result.numShared,
                                           let failures = result.failures {
                                            self.sentInvites = .init(invitationsSent: numShared, nonNeevanEmails: failures)
                                        }
                                    }
                                }) {
                                    Text("Send")
                                    Image(systemName: "arrow.right")
                                }
                            } else {
                                Text("Enable link sharing and send?")
                                if publicityController.isUpdating {
                                    LoadingView("Enabling…", mini: true)
                                        .padding(.vertical, -5)
                                } else {
                                    Button(action: {
                                        publicityController.hasPublicACL = true
                                    }) {
                                        Text("Enable Public Link")
                                    }
                                }
                            }
                        }
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding()
                    }
                    Spacer()
                }
                .navigationBarItems(
                    trailing: Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                )
                .navigationBarTitleDisplayMode(.inline)
                .background(
                    Color(UIColor.systemGroupedBackground)
                        .edgesIgnoringSafeArea(.all)
                )
            } else {
                Form {
                    if canEditSettings {
                        SpaceInviteView(invite: $invite, suggestions: suggestionsController)
                        if suggestionsController.query.isEmpty {
                            if invite.selected.isEmpty {
                                SharedWithView(users: space.acl!, canEdit: canEditSettings, spaceId: spaceId, onUpdate: onUpdate)
                                PublicToggleView(
                                    isPublic: $publicityController.hasPublicACL,
                                    isUpdating: publicityController.isUpdating,
                                    spaceId: spaceId
                                )
                            } else {
                                MultilineTextField("Optional message…", text: $invite.note)
                            }
                        } else {
                            Section(header: Text("Suggestions")) {
                                if let users = suggestionsController.data, !users.isEmpty {
                                    ForEach(users) { user in
                                        Button {
                                            invite.selected.append(user)
                                            suggestionsController.query = ""
                                        } label: {
                                            UserDetailView(user).accentColor(.primary)
                                        }
                                    }
                                } else {
                                    let synthetic = ContactSuggestionController.Suggestion(displayName: "", email: suggestionsController.query, pictureUrl: "")
                                    Button {
                                        invite.selected.append(synthetic)
                                        suggestionsController.query = ""
                                    } label: {
                                        UserDetailView(synthetic).accentColor(.primary)
                                    }
                                }
                            }
                        }
                    } else {
                        SharedWithView(users: space.acl!, canEdit: canEditSettings, spaceId: spaceId, onUpdate: onUpdate)
                    }
                }
                .navigationTitle(canEditSettings ? "Share This Space" : "Shared with")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(
                    leading: Group {
                        if !invite.selected.isEmpty {
                            Button("Cancel") { invite.selected = [] }
                                .font(.body)
                        }
                    },
                    trailing: Group {
                        if invite.selected.isEmpty {
                            Button("Done") { presentationMode.wrappedValue.dismiss() }
                        } else {
                            Button("Share") {
                                guard !invite.selected.isEmpty else { return }

                                sendingInvites = AddSpaceSoloAcLsMutation(
                                    space: spaceId,
                                    shareWith: invite.selected.map { .init(email: $0.email, acl: invite.shareType) },
                                    note: invite.note
                                ).perform { result in
                                    sendingInvites = nil
                                    guard case .success(let data) = result,
                                          let result = data.addSpaceSoloAcLs else {
                                        onUpdate(nil)
                                        return
                                    }
                                    // TODO: handle when changedACLCount + nonNeevanEmails.count < invite.selected.count
                                    sentInvites = .init(
                                        invitationsSent: result.changedAclCount ?? 0,
                                        nonNeevanEmails: result.nonNeevanEmails!
                                    )
                                    onUpdate(nil)
                                }
                            }
                        }
                    }
                )
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onDisappear { onUpdate(nil) }
        .presentation(isModal: sendingInvites != nil || (!invite.selected.isEmpty && sentInvites == nil))
    }
}

struct ShareSpaceView_Previews: PreviewProvider {
    static var previews: some View {
        ShareSpaceView(space: testSpace, id: String(repeating: "space123", count: 10), onUpdate: { _ in })
        ShareSpaceView(space: testSpace, id: String(repeating: "space123", count: 10), onUpdate: { _ in }, sendingInvites: Apollo.EmptyCancellable(), sentInvites: .init(invitationsSent: 0, nonNeevanEmails: ["jed@neeva.co"]))
        ShareSpaceView(space: testSpace2, id: String(repeating: "space123", count: 10), onUpdate: { _ in }, sentInvites: .init(invitationsSent: 1, nonNeevanEmails: ["jed@neeva.co"]))
        ShareSpaceView(space: testSpace, id: String(repeating: "space123", count: 10), onUpdate: { _ in }, sentInvites: .init(invitationsSent: 0, nonNeevanEmails: ["jed@neeva.co"]))
        ShareSpaceView(space: testSpace, id: String(repeating: "space123", count: 10), onUpdate: { _ in }, sentInvites: .init(invitationsSent: 4, nonNeevanEmails: []))
    }
}
