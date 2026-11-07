import SwiftUI
import AppKit

public struct ClipboardFlyoutView: View {
    public let onItemChosen: (ClipboardItem) -> Void
    public let onCloseRequested: () -> Void

    @ObservedObject private var store = ClipboardStore.shared
    @State private var selectedIndex: Int = 0
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
                        LazyVStack(spacing: 6) {
                            ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                                ClipboardCardView(
                                    item: item,
                                    isSelected: index == selectedIndex,
                                    onSelect: {
                                        selectedIndex = index
                                        onItemChosen(item)
                                    },
                                    onTogglePin: {
                                        store.togglePin(for: item)
                                    },
                                    onDelete: {
                                        store.deleteItem(item)
                                        if selectedIndex >= store.items.count - 1 && selectedIndex > 0 {
                                            selectedIndex -= 1
                                        }
                                    }
                                )
                                .id(index)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: selectedIndex) { _, newIndex in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }

            Divider()
                .opacity(0.3)

            // Footer Status
            HStack(spacing: 8) {
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
        .onKeyPress(.downArrow) {
            if selectedIndex < store.items.count - 1 {
                selectedIndex += 1
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 {
                selectedIndex -= 1
            }
            return .handled
        }
        .onKeyPress(.return) {
            if store.items.indices.contains(selectedIndex) {
                onItemChosen(store.items[selectedIndex])
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.delete) {
            if !isSearchFocused && store.items.indices.contains(selectedIndex) {
                let item = store.items[selectedIndex]
                store.deleteItem(item)
                if selectedIndex >= store.items.count - 1 && selectedIndex > 0 {
                    selectedIndex -= 1
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(KeyEquivalent("f"), phases: .down) { press in
            if press.modifiers.contains(.command) {
                isSearchFocused = true
                return .handled
            }
            return .ignored
        }
        .onAppear {
            store.refresh()
            selectedIndex = 0
        }
    }
}
