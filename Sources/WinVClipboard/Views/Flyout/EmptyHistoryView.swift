import SwiftUI

public struct EmptyHistoryView: View {
    public var hasSearchQuery: Bool

    public var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: hasSearchQuery ? "magnifyingglass" : "clipboard")
                .font(.system(size: 38, weight: .light))
                .foregroundColor(.secondary.opacity(0.7))

            Text(hasSearchQuery ? "No matching clips" : "Your clipboard is empty")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)

            Text(hasSearchQuery ? "Try searching for a different keyword." : "Copy text, links, or images anywhere to see them saved here.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
