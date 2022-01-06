// Copyright Neeva. All rights reserved.

import SDWebImageSwiftUI
import Shared
import SwiftUI

struct InlineSearchProductItem: View {
    let product: InlineSearchProduct
    @Environment(\.onOpenURL) var onOpenURL

    var body: some View {
        Button(action: onClick) {
            ZStack(alignment: .top) {
                VStack {
                    WebImage(url: URL(string: product.thumbnailURL))
                        .placeholder {
                            Rectangle().foregroundColor(.gray)
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140, height: 130, alignment: .center)
                        .clipped()
                        .cornerRadius(11, corners: .top)

                    Text(product.productName)
                        .font(.system(size: 14))
                        .foregroundColor(Color.label)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 8)
                }
                if let price = product.price {
                    VStack {
                        HStack {
                            Text(price.components(separatedBy: ".").first ?? price)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.label)
                                .padding(4)
                                .background(Capsule().fill(Color.DefaultBackground))
                                .padding(10)
                            Spacer()
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: 140, height: 180, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(Color(light: Color.ui.gray91, dark: Color(hex: 0x383b3f)), lineWidth: 1)
            )
        }
    }

    func onClick() {
        onOpenURL(product.actionURL)
    }

}

struct InlineSearchProductList: View {
    let inlineSearchProducts: [InlineSearchProduct]

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(inlineSearchProducts, id: \.actionURL) { item in
                    InlineSearchProductItem(product: item)
                }
            }
        }
    }
}
