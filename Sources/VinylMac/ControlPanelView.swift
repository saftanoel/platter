import SwiftUI

/// Settings surface for the app. Vinyl normally lives in the menu bar, but a full
/// menu bar can leave the status item with nowhere to go, so this panel is also
/// reachable by re-opening Vinyl from Finder or the Dock.
struct ControlPanelView: View {
    @ObservedObject var settings: Settings
    @State var showOnDesktop: Bool
    @State var launchAtLogin: Bool

    var onToggleDesktop: (Bool) -> Void
    var onToggleLogin: (Bool) -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().padding(.vertical, 14)

            Toggle("Show on desktop", isOn: $showOnDesktop)
                .onChange(of: showOnDesktop) { _, value in onToggleDesktop(value) }

            Text("Draws the turntable behind your desktop icons.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            Picker("Background", selection: $settings.backdrop) {
                ForEach(BackdropStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .padding(.top, 14)

            Text("Album colour tints the desktop with the current cover's background.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, value in onToggleLogin(value) }
                .padding(.top, 12)

            Text("Vinyl reads the current track from Spotify or Music. No login needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            Spacer(minLength: 18)

            HStack {
                Spacer()
                Button("Quit Vinyl", role: .destructive, action: onQuit)
                    .keyboardShortcut("q")
            }
        }
        .toggleStyle(.switch)
        .padding(22)
        .frame(width: 340, height: 330)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "opticaldisc.fill")
                .font(.system(size: 30))
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Vinyl").font(.title2.weight(.semibold))
                Text(versionString).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }
}
