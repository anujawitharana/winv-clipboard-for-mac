import SwiftUI
import AppKit

public struct ClipboardFlyoutView: View {
    public let onItemChosen: (ClipboardItem) -> Void
    public let onCloseRequested: () -> Void

    @ObservedObject private var store = ClipboardStore.shared
    @FocusState private var isSearchFocused: Bool

    public init(onItemChosen: @escaping (ClipboardItem) -> Void, onCloseRequested: @escaping () -> Void) {
        self.onItemChosen = onItemChosen
        self.onCloseRequested = onCloseRequested
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            FlyoutHeaderView(
                searchText: $store.searchQuery,
                onClearAll: {
                    store.clearAllUnpinned()
                },
                onOpenSettings: {
                    SettingsWindowController.shared.show()
                    onCloseRequested()
                },
                isSearchFocused: $isSearchFocused
            )

            Divider()
                .opacity(0.3)

            // Content Body
            if store.items.isEmpty {
                EmptyHistoryView(hasSearchQuery: !store.searchQuery.isEmpty)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 6) {
                            ForEach(store.items) { item in
                                ClipboardCardView(
                                    item: item,
                                    isSelected: store.selectedItem?.id == item.id,
                                    onSelect: {
                                        store.selectItem(item)
                                        onItemChosen(item)
                                    },
                                    onTogglePin: {
                                        store.togglePin(for: item)
                                    },
                                    onDelete: {
                                        store.deleteItem(item)
                                    }
                                )
                                .id(item.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: store.selectedItem?.id) { _, newId in
                        if let id = newId {
                            withAnimation(.easeInOut(duration: 0.1)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
            }

            Divider()
                .opacity(0.3)

            // Footer Status
            HStack(spacing: 8) {
                Text("↑/↓ navigate")
                Text("•")
                Text("↵ to paste")
                Text("•")
                Text("⌫ to delete")
                Text("•")
                Text("Esc to close")
                Spacer()
                Text("\(store.items.count) items")
            }
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.02))
        }
        .frame(width: 380, height: 520)
        .background(
            AcrylicBackground()
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onReceive(NotificationCenter.default.publisher(for: .focusClipboardSearch)) { _ in
            isSearchFocused = true
        }
        .onAppear {
            store.refresh()
        }
    }
}
