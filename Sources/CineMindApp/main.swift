import AppUI
import Application
import AppKit
import SwiftUI

struct CineMindApp: App {
    @StateObject private var viewModel = AppShellViewModel()
    @StateObject private var playbackKeyboardShortcuts = PlaybackKeyboardShortcutMonitor()
    @StateObject private var tmdbSettingsViewModel = TMDBSettingsViewModel()
    @StateObject private var aiSettingsViewModel = AISettingsViewModel()
    @State private var playbackRuntime: CineMindPlaybackRuntime?
    @State private var libraryExporter: (any LibraryExporting)?
    @State private var libraryExportDestinationPicker: (any LibraryExportDestinationPicking)?
    @State private var isExportingLibrary = false
    @State private var libraryExportAlert: LibraryExportAlert?
    @FocusedValue(\.libraryCommandActions) private var libraryCommandActions

    var body: some Scene {
        WindowGroup {
            CineMindRootView(
                viewModel: viewModel,
                playbackSurface: playbackSurface
            )
                .task {
                    activateApplication()
                    playbackKeyboardShortcuts.install(
                        togglePlayPause: { togglePlayPause() },
                        seekRelative: { seekRelative(byMS: $0) }
                    )
                    startAppIfNeeded()
                }
                .alert(item: $libraryExportAlert) { alert in
                    Alert(
                        title: Text(alert.title),
                        message: Text(alert.message),
                        dismissButton: .default(Text("OK"))
                    )
                }
        }
        .commands {
            CommandMenu("Library") {
                Button("Add Folder") {
                    libraryCommandActions?.addFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(!(libraryCommandActions?.canAddFolder ?? false))

                Button("Scan Library") {
                    libraryCommandActions?.scanLibrary()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!(libraryCommandActions?.canScanLibrary ?? false))

                Button("Toggle Grid/List") {
                    libraryCommandActions?.togglePresentation()
                }
                .keyboardShortcut("g", modifiers: [.command, .option])
                .disabled(!(libraryCommandActions?.canTogglePresentation ?? false))

                Button("Toggle Inspector") {
                    libraryCommandActions?.toggleInspector()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(libraryCommandActions == nil)

                Divider()

                Button("Export Library...") {
                    exportLibrary()
                }
                .disabled(
                    isExportingLibrary
                        || libraryExporter == nil
                        || libraryExportDestinationPicker == nil
                )
            }

            CommandMenu("Playback") {
                Button("Toggle Play/Pause") {
                    togglePlayPause()
                }

                Button("Seek Backward 10 Seconds") {
                    seekRelative(byMS: -10_000)
                }

                Button("Seek Forward 10 Seconds") {
                    seekRelative(byMS: 10_000)
                }
            }
        }

        Settings {
            CineMindSettingsView(
                tmdbViewModel: tmdbSettingsViewModel,
                aiViewModel: aiSettingsViewModel
            )
        }
    }

    @MainActor
    private func exportLibrary() {
        guard !isExportingLibrary,
              let libraryExporter,
              let libraryExportDestinationPicker else {
            return
        }

        isExportingLibrary = true
        Task { @MainActor in
            defer {
                isExportingLibrary = false
            }

            do {
                guard let destinationPath = try await libraryExportDestinationPicker
                    .pickLibraryExportDestination() else {
                    return
                }

                let result = try await libraryExporter.exportLibrary(to: destinationPath)
                let fileName = URL(fileURLWithPath: result.destinationPath).lastPathComponent
                libraryExportAlert = LibraryExportAlert(
                    title: "Library Exported",
                    message: "Exported \(result.mediaItemCount) items to \(fileName). This JSON file is not a complete backup and cannot currently be imported."
                )
            } catch {
                libraryExportAlert = LibraryExportAlert(
                    title: "Export Failed",
                    message: (error as? LocalizedError)?.errorDescription
                        ?? "CineMind could not export the library."
                )
            }
        }
    }

    private var playbackSurface: AnyView? {
        guard let playbackRuntime else {
            return nil
        }

        return AnyView(
            PlaybackAVFoundationSurfaceView(backend: playbackRuntime.backend)
        )
    }

    @MainActor
    private func activateApplication() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    private var playbackController: (any PlaybackApplicationControlling)? {
        playbackRuntime?.controller ?? viewModel.environment?.playbackController
    }

    @MainActor
    private func togglePlayPause() {
        guard let controller = playbackController else {
            return
        }

        Task {
            await controller.togglePlayPause()
        }
    }

    @MainActor
    private func seekRelative(byMS deltaMS: Int) {
        guard let controller = playbackController else {
            return
        }

        Task {
            await controller.seekRelative(byMS: deltaMS)
        }
    }

    @MainActor
    private func startAppIfNeeded() {
        guard StartupRunGuard.claim() else {
            return
        }

        viewModel.markLoading()

        do {
            let startup = try CineMindAppEnvironmentFactory.start()
            playbackRuntime = startup.playbackRuntime
            libraryExporter = startup.libraryExporter
            libraryExportDestinationPicker = startup.libraryExportDestinationPicker
            tmdbSettingsViewModel.setManager(startup.tmdbSettingsManager)
            aiSettingsViewModel.setManager(startup.aiSettingsManager)
            viewModel.markReady(environment: startup.appShellEnvironment)
        } catch {
            tmdbSettingsViewModel.setManager(nil)
            aiSettingsViewModel.setManager(nil)
            viewModel.markFailed(
                CineMindAppEnvironmentFactory.startupFailureMessage(for: error)
            )
        }
    }
}

private struct LibraryExportAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
private enum StartupRunGuard {
    private static var didRun = false

    static func claim() -> Bool {
        guard !didRun else {
            return false
        }

        didRun = true
        return true
    }
}

CineMindApp.main()
