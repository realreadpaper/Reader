import SwiftUI

struct BookRowView: View {
    let book: Book

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: "#D5C8B0"))
                .frame(width: 36, height: 48)
                .overlay(
                    Text(String(book.title.prefix(2)))
                        .font(.caption2)
                        .foregroundStyle(Color(hex: "#6B5A40"))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text("读到 \(Int(book.progress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
