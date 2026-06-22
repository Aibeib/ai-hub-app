import SwiftUI

struct PrivacyAndLogsView: View {
    @State private var thirdPartyAPIEnabled = true
    @State private var localNetworkEnabled = false

    var body: some View {
        Form {
            Section("Data controls") {
                Toggle("Allow third-party API calls", isOn: $thirdPartyAPIEnabled)
                Toggle("Enable local network discovery", isOn: $localNetworkEnabled)
                Button("Clear chat history", role: .destructive) {}
                Button("Clear tool execution logs", role: .destructive) {}
            }

            Section("Audit policy") {
                Text("Tool execution logs are retained for 30 days. Deleted conversations are soft-deleted for 7 days before purge.")
                    .foregroundStyle(.secondary)
            }

            Section("High-risk actions") {
                Text("Code execution, file modification, deletion, and remote device commands require a fresh confirmation every time.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Privacy")
    }
}

