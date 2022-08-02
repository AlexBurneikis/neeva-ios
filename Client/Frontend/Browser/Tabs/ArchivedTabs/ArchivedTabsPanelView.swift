// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Defaults
import Shared
import SwiftUI

struct ArchivedTabsSectionHeader: View {
    let section: ArchivedTabTimeSection

    var body: some View {
        HStack {
            Text(section.rawValue)
                .fontWeight(.medium)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.leading)
        .padding(.vertical, 8)
    }
}

struct ArchivedTabsPanelView: View {
    @ObservedObject var model: ArchivedTabsPanelModel
    @Default(.archivedTabsDuration) var archivedTabsDuration
    @State var showArchivedTabsSettings = false
    @State private var confirmationShow = false
    let onDismiss: () -> Void
    private let clearAllArchiveButtonTitle = "Are you sure you want to close all archived tabs?"

    var archivedTabsLabel: LocalizedStringKey {
        switch archivedTabsDuration {
        case .week:
            return "After 7 Days"
        case .month:
            return "After 30 Days"
        case .forever:
            return "Never"
        }
    }

    var clearAllArchivesButton: some View {
        HStack(spacing: 0) {
            Text("Clear All Archived Tabs")
                .withFont(.bodyLarge)
                .foregroundColor(model.numOfArchivedTabs < 1 ? .gray : .red)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 10)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    var clearAllArchiveButtonText: String {
        return "Close \(model.numOfArchivedTabs) \(model.numOfArchivedTabs > 1 ? "Tabs" : "Tab")"
    }

    var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                Button(action: {
                    showArchivedTabsSettings = true
                }) {
                    HStack(spacing: 0) {
                        Text("Archive tabs")
                            .withFont(.bodyLarge)
                            .foregroundColor(.label)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 10)
                        Spacer()
                        Text(archivedTabsLabel)
                            .withFont(.bodyLarge)
                            .foregroundColor(.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                        Symbol(decorative: .chevronRight, size: 16)
                            .foregroundColor(.secondaryLabel)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                }

                Color.groupedBackground.frame(height: 1)

                Button(action: {
                    confirmationShow = true
                }) {
                    if #available(iOS 15.0, *) {
                        clearAllArchivesButton
                            .confirmationDialog(
                                clearAllArchiveButtonTitle,
                                isPresented: $confirmationShow,
                                titleVisibility: .visible
                            ) {
                                Button(
                                    clearAllArchiveButtonText,
                                    role: .destructive
                                ) {
                                    model.clearArchivedTabs()
                                    ClientLogger.shared.logCounter(
                                        .clearArchivedTabs,
                                        attributes: EnvironmentHelper.shared.getAttributes())
                                }
                            }
                    } else {
                        clearAllArchivesButton
                            .actionSheet(isPresented: $confirmationShow) {
                                ActionSheet(
                                    title: Text(clearAllArchiveButtonTitle),
                                    buttons: [
                                        .destructive(
                                            Text(
                                                clearAllArchiveButtonText
                                            )
                                        ) {
                                            model.clearArchivedTabs()
                                        },
                                        .cancel(),
                                    ]
                                )
                            }
                    }
                }
                    .disabled(model.numOfArchivedTabs < 1)

                NavigationLink(isActive: $showArchivedTabsSettings) {
                    ArchivedTabSettings()
                } label: {
                    EmptyView()
                }

                Color.secondarySystemFill
                    .frame(height: 8)
            }

            // Archived tabs
            VStack(spacing: 0) {
                ForEach(ArchivedTabTimeSection.allCases, id: \.self) { section in
                    let itemsInSection = model.groupedSites.itemsForSection(section: section)

                    if itemsInSection.count > 0 {
                        Section(header: ArchivedTabsSectionHeader(section: section)) {
                            ArchivedTabsListSectionView(
                                listSectionModel: ArchivedTabsListSectionViewModel(
                                    itemsInSection: itemsInSection),
                                tabManager: model.tabManager, section: section
                            )
                            .environmentObject(model)
                        }
                    }
                }
            }

        }
    }

    var body: some View {
        NavigationView {
            content
                .accessibilityIdentifier("archivedTabsPanel")
                .navigationTitle("Archived Tabs")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    Button {
                        onDismiss()
                    } label: {
                        Text("Done")
                    }
                }
                .introspectNavigationController { target in
                    target.navigationBar.backgroundColor = UIColor.systemBackground
                }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            model.loadData()
        }
    }
}
