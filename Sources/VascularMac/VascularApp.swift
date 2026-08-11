import SwiftUI

final class VascularAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: InstrumentModel?
    private var didShutDown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !didShutDown {
            didShutDown = true
            model?.shutdown()
        }
        return .terminateNow
    }
}

@main
struct VascularApp: App {
    @StateObject private var model = InstrumentModel()
    @NSApplicationDelegateAdaptor(VascularAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            MatrixView(model: model)
                .frame(minWidth: 720, minHeight: 680)
                .onAppear { appDelegate.model = model }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("ParallelLives") {
                Button("Remove selected chain") { model.drainSelected() }
                    .keyboardShortcut(.delete, modifiers: [])
                Button("Panic") { model.panic() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
    }
}
