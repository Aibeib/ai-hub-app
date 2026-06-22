import SwiftUI

struct MacCompanionRootView: View {
    @Environment(MacCompanionRuntime.self) private var runtime

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("AI Agent Hub Mac Companion")
                    .font(.largeTitle.bold())
                Text("Accepts approved local-network commands from trusted iOS devices. The current implementation uses a sandbox-safe mock executor.")
                    .foregroundStyle(.secondary)
            }

            Toggle("Enable device receiving", isOn: Binding(
                get: { runtime.receivingEnabled },
                set: { runtime.receivingEnabled = $0 }
            ))
            .toggleStyle(.switch)

            Button("Run sandbox demo command") {
                Task { await runtime.executeDemoCommand() }
            }
            .disabled(!runtime.receivingEnabled)

            Text(runtime.latestOutput)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer()
        }
        .padding(28)
        .frame(minWidth: 560, minHeight: 360)
    }
}

