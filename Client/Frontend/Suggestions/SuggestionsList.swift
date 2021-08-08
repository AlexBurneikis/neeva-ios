// Copyright Neeva. All rights reserved.

import Shared
import Storage
import SwiftUI

struct SuggestionsList: View {
    static let placeholderNavSuggestion = NavSuggestion(
        url: "https://neeva.com", title: "PlaceholderLongTitleOneWord")

    @EnvironmentObject private var suggestionModel: SuggestionModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                if let lensOrBang = suggestionModel.activeLensBang,
                    let description = lensOrBang.description
                {
                    Section(
                        header: Group {
                            switch lensOrBang.type {
                            case .bang:
                                Text("Search on \(description)")
                            default:
                                Text(description)
                            }
                        }.textCase(nil)
                    ) {
                        QuerySuggestionsList()
                    }
                } else {
                    TabSuggestionsList()

                    if suggestionModel.suggestions.isEmpty && suggestionModel.shouldShowSuggestions {
                        PlaceholderSuggestions()
                    } else {
                        TopSuggestionsList()
                        QuerySuggestionsList()
                        UrlSuggestionsList()
                    }
                }

                NavSuggestionsList()
            }
        }
    }
}

struct SuggestionsList_Previews: PreviewProvider {
    static var previews: some View {
        let suggestions = [
            Suggestion.query(
                .init(
                    type: .standard, suggestedQuery: "hello world", boldSpan: [], source: .unknown))
        ]
        let history = [
            Site(url: "https://neeva.com", title: "Neeva", id: 1),
            Site(url: "https://neeva.com", title: "", id: 2),
            Site(url: "https://google.com", title: "Google", id: 3),
        ]
        Group {
            SuggestionsList()
                .environmentObject(SuggestionModel(previewSites: history))
            SuggestionsList()
                .environmentObject(SuggestionModel(previewSites: history))
            SuggestionsList()
                .environmentObject(SuggestionModel(previewSites: history))
        }.previewLayout(.fixed(width: 375, height: 250))
    }
}
