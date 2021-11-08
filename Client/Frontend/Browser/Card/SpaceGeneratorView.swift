// Copyright Neeva. All rights reserved.

import Shared
import SwiftUI

struct SpaceGeneratorHeader: View {
    let generators: [SpaceGeneratorData]

    var body: some View {
        VStack(spacing: 0) {
            Text("News alerts")
                .withFont(.headingSmall)
                .foregroundColor(.label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.secondaryBackground)
        }
    }
}

struct SpaceGeneratorView: View {
    @EnvironmentObject var spaceCardModel: SpaceCardModel
    let generator: SpaceGeneratorData

    var canEdit: Bool {
        guard let space = spaceCardModel.detailedSpace?.space else {
            return false
        }

        return space.ACL >= .edit
    }

    var body: some View {
        if let query = generator.query {
            HStack(spacing: 10) {
                Symbol(decorative: .bell, style: .labelSmall)
                    .foregroundColor(.label)
                    .frame(width: 24, height: 24)
                    .background(Color.secondaryBackground)
                    .clipShape(Circle())
                Text(query)
                    .withFont(.headingSmall)
                    .foregroundColor(.label)
                Spacer()
                if canEdit {
                    Button(
                        action: {
                            guard let space = spaceCardModel.detailedSpace?.space,
                                let index = space.generators?.index(
                                    where: { $0.id == generator.id })
                            else {
                                return
                            }

                            space.generators?.remove(at: index)
                            spaceCardModel.detailedSpace?.objectWillChange.send()
                            spaceCardModel.deleteGeneratorFromSpace(
                                spaceID: space.id.id, generatorID: generator.id)

                        },
                        label: {
                            Symbol(decorative: .trash, style: .headingSmall)
                                .foregroundColor(.secondaryLabel)
                        })
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color.DefaultBackground)
        }
    }
}
