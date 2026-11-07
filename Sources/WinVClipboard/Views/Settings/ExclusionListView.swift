import SwiftUI
import AppKit

public struct ExclusionListView: View {
    @State private var newBundleID: String = ""
    @State private var customIDs: [String] = []

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Excluded Applications")
                .font(.system(size: 14, weight: .semibold))

            Text("Clips copied from excluded applications will never be stored in your clipboard history.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            // Protected Defaults
            VStack(alignment: .leading, spacing: 6) {
                Text("Built-in Password Managers (Always Excluded)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(["1Password", "Bitwarden", "Apple Keychain", "KeePassXC", "LastPass", "Dashlane"], id: \.self) { name in
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                            Text(name)
                                .font(.system(size: 11))
                            Spacer()
                        }
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.04))
                        )
                    }
                }
            }

            Divider()

            // Custom Exclusions
            VStack(alignment: .leading, spacing: 8) {
                Text("Custom Excluded Bundle Identifiers")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                HStack {
                    TextField("e.g. com.example.app", text: $newBundleID)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))

                    Button("Add") {
                        let trimmed = newBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            PrivacyFilter.shared.addExcludedBundleID(trimmed)
                            newBundleID = ""
                            loadCustom()
                        }
                    }
                    .disabled(newBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Menu("Add Running App...") {
                        ForEach(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }, id: \.processIdentifier) { app in
                            if let bundleID = app.bundleIdentifier, let name = app.localizedName {
                                Button("\(name) (\(bundleID))") {
                                    PrivacyFilter.shared.addExcludedBundleID(bundleID)
                                    loadCustom()
                                }
                            }
                        }
                    }
                }

                if customIDs.isEmpty {
                    Text("No custom applications added.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    List {
                        ForEach(customIDs, id: \.self) { id in
                            HStack {
                                Text(id)
                                    .font(.system(size: 11, design: .monospaced))
                                Spacer()
                                Button(action: {
                                    PrivacyFilter.shared.removeExcludedBundleID(id)
                                    loadCustom()
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10))
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .onAppear {
            loadCustom()
        }
    }

    private func loadCustom() {
        let all = PrivacyFilter.shared.allExcludedBundleIDs()
        let defaults = PrivacyFilter.defaultExcludedBundleIdentifiers
        customIDs = Array(all.subtracting(defaults)).sorted()
    }
}
