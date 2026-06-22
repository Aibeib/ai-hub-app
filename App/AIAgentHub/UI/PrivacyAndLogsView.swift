import SwiftUI

struct PrivacyAndLogsView: View {
    @Environment(AppRuntime.self) private var runtime
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

            Section("Tool execution logs") {
                if runtime.auditEntries.isEmpty {
                    Text("No tool calls yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(runtime.auditEntries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.toolName)
                                .font(.headline)
                            Text("\(entry.riskLevel.rawValue) · \(entry.decision.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(entry.summary)
                                .font(.caption)
                        }
                    }
                }
            }

            Section("High-risk actions") {
                Text("Code execution, file modification, deletion, and remote device commands require a fresh confirmation every time.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Privacy")
    }
}
