import SwiftUI

// MARK: - Live Status Bar

struct LiveStatusBar: View {
    @ObservedObject var watcher: ControlMasterWatcher

    var body: some View {
        HStack(spacing: 8) {
            statusIndicator
            statusText
            Spacer()

            if case .error = watcher.status {
                Button("Reconnect") {
                    watcher.reconnect()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(statusBackground)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch watcher.status {
        case .idle:
            Circle()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)

        case .connecting:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 8, height: 8)

        case .watching:
            PulsingDot()

        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.caption2)
        }
    }

    private var statusText: some View {
        Group {
            switch watcher.status {
            case .idle:
                Text("Not watching")
            case .connecting:
                Text("Connecting…")
            case .watching:
                Text("Watching \(watcher.host)")
            case .error(let msg):
                Text(msg)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    private var statusBackground: Color {
        switch watcher.status {
        case .error: return Color.orange.opacity(0.08)
        case .watching: return Color.green.opacity(0.05)
        default: return Color.clear
        }
    }
}

// MARK: - Pulsing Green Dot

struct PulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 8, height: 8)
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(
                .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}
