import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let viewModel = QuotaViewModel()
    private lazy var floatingWindow = FloatingQuotaWindowController(viewModel: viewModel)
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: "ChatGPT 额度")
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.title = " 读取中"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 245, height: 166)

        observeStatusTitle()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            Task { await viewModel.refresh() }
            popover.contentViewController = NSHostingController(
                rootView: QuotaPopoverView(
                    viewModel: viewModel,
                    isFloatingVisible: floatingWindow.isVisible,
                    toggleFloating: { [weak self] in
                        self?.floatingWindow.toggle()
                        self?.popover.performClose(nil)
                    }
                )
            )
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func observeStatusTitle() {
        viewModel.$state
            .combineLatest(viewModel.$isRefreshing)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                guard let self else { return }
                statusItem.button?.title = " \(viewModel.statusTitle)"
            }
            .store(in: &cancellables)
    }
}
