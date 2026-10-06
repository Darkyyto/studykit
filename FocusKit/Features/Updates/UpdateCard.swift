import SwiftUI

struct UpdateCard: View {
    let release: Updater.Release
    @Environment(Updater.self) private var updater
    @Environment(\.closeCard) private var close
    @State private var copied = false

    private let tint = FocusMode.flight.palette.deep

    var body: some View {
        VStack(spacing: 22) {
            header

            switch updater.state {
            case .downloading(let fraction):
                downloading(fraction)
            case .ready(let url):
                ready(url)
            case .failed(let message):
                failure(message)
            default:
                offer
            }
        }
        .padding(30)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .animation(Motion.standard, value: updater.state)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image("Logo")
                .resizable()
                .interpolation(.high)
                .frame(width: 76, height: 76)
                .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
            VStack(spacing: 4) {
                Text("FocusKit \(release.version)")
                    .font(.rounded(26, weight: .bold))
                    .displayTracking(26)
                    .foregroundStyle(Palette.ink)
                Text("You have \(Updater.currentVersion)")
                    .font(.rounded(13, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    private var offer: some View {
        VStack(spacing: 20) {
            if !release.notes.isEmpty {
                ScrollView {
                    Text(LocalizedStringKey(release.notes))
                        .font(.rounded(13, weight: .medium))
                        .foregroundStyle(Palette.ink.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 150)
                .padding(14)
                .background(Palette.canvas, in: .rect(cornerRadius: 16))
            }

            promise

            VStack(spacing: 10) {
                Button {
                    updater.install(release)
                } label: {
                    Text("Update Now")
                        .font(.rounded(16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(tint)
                .keyboardShortcut(.defaultAction)

                command
                HStack(spacing: 18) {
                    Button("Later") { close() }
                        .keyboardShortcut(.cancelAction)
                    Button("Skip This Version") { updater.skip(release) }
                }
                .buttonStyle(.plain)
                .font(.rounded(13, weight: .semibold))
                .foregroundStyle(Palette.inkSecondary)
            }
        }
        .transition(.blurReplace)
    }

    private func downloading(_ fraction: Double) -> some View {
        VStack(spacing: 12) {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(tint)
            HStack {
                Text("Downloading")
                Spacer()
                Text("\(Int(fraction * 100))%")
                    .contentTransition(.numericText())
            }
            .font(.rounded(13, weight: .semibold))
            .foregroundStyle(Palette.inkSecondary)
            Text("You can keep working. FocusKit tells you when it is ready.")
                .font(.rounded(12, weight: .medium))
                .foregroundStyle(Palette.inkTertiary)
            Button("Hide") { close() }
                .buttonStyle(.plain)
                .font(.rounded(13, weight: .semibold))
                .foregroundStyle(Palette.inkSecondary)
                .keyboardShortcut(.cancelAction)
        }
        .transition(.blurReplace)
    }

    private func ready(_ url: URL) -> some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                step(1, "FocusKit quits and the installer opens.")
                step(2, "Drag FocusKit onto Applications and choose Replace.")
                step(3, "Open FocusKit again. Everything is where you left it.")
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.canvas, in: .rect(cornerRadius: 18))

            promise

            Button {
                updater.openInstaller(url)
            } label: {
                Text("Install and Quit")
                    .font(.rounded(16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(tint)
            .keyboardShortcut(.defaultAction)

            Button("Not Now") { close() }
                .buttonStyle(.plain)
                .font(.rounded(13, weight: .semibold))
                .foregroundStyle(Palette.inkSecondary)
                .keyboardShortcut(.cancelAction)
        }
        .transition(.blurReplace)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text(message)
                .font(.rounded(14, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
            Button("Open Release Page") {
                NSWorkspace.shared.open(release.page)
                close()
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .transition(.blurReplace)
    }

    private var command: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("curl -fsSL https://raw.githubusercontent.com/\(Updater.repositoryName)/main/Scripts/install.sh | sh", forType: .string)
            copied = true
        } label: {
            Label(copied ? "Copied. Paste it in Terminal." : "Or copy the one-line Terminal update", systemImage: copied ? "checkmark" : "terminal")
                .font(.rounded(12, weight: .semibold))
                .foregroundStyle(Palette.inkSecondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }

    private var promise: some View {
        Label("Your sessions, lectures and notes stay on this Mac. A backup is saved first.", systemImage: "lock.shield.fill")
            .font(.rounded(12, weight: .medium))
            .foregroundStyle(Palette.inkSecondary)
            .multilineTextAlignment(.leading)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.rounded(12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(tint, in: .circle)
            Text(text)
                .font(.rounded(14, weight: .medium))
                .foregroundStyle(Palette.ink)
        }
    }
}
