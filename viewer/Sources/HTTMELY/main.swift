import AppKit
import WebKit

struct Report: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let fileURL: URL
}

struct ReportGroup {
    let title: String
    let reports: [Report]
}

struct FolderMode: Identifiable, Equatable {
    let id: String
    let folderURL: URL
    var title: String

    var subtitle: String {
        "Folder HTML/Markdown viewer"
    }
}

enum SourceMode: Equatable {
    case welcome
    case reports
    case folder(String)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let appDisplayName = "HTTMELY"
    private let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
    private var window: NSWindow!
    private var webView: WKWebView!
    private var splitView: NSSplitView!
    private var appSidebar: NSView!
    private var headerView: NSView!
    private var headerHeightConstraint: NSLayoutConstraint!
    private var sidebarRootStack: NSStackView!
    private var sidebarTitleLabel: NSTextField!
    private var sidebarSubtitleLabel: NSTextField!
    private var sidebarItemStack: NSStackView!
    private var placesPopup: NSPopUpButton!
    private var contentsButton: NSButton?
    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private var sidebarButtons: [String: NSButton] = [:]
    private var modeMenu: NSMenu?
    private var welcomeModeMenuItem: NSMenuItem?
    private var reportsModeMenuItem: NSMenuItem?
    private var folderModeMenuItems: [String: NSMenuItem] = [:]
    private var topBarMenuItem: NSMenuItem?
    private var placesManagerWindow: NSWindow?
    private var placesManagerTableView: NSTableView?
    private var placesManagerActionButtons: [NSButton] = []
    private var keyMonitor: Any?
    private var selectedReport: Report?
    private var sourceMode: SourceMode = .welcome
    private var folderModes: [FolderMode] = []
    private var currentItems: [Report] = []
    private var currentReadRoot: URL!
    private var isAppSidebarVisible = true
    private var isReportContentsVisible = false
    private var isTopBarVisible = false
    private let defaults = UserDefaults.standard
    private lazy var welcomeRoot = resolveWelcomeRoot()
    private lazy var reportRoot = resolveReportRoot()
    private lazy var defaultBlogsRoot = resolveDefaultFolderRoot()
    private let folderModesDefaultsKey = "HTTMELY.folderModePaths"
    private let folderDefaultsKey = "HTTMELY.folderModePath"
    private let legacyBlogsFolderDefaultsKey = "HTTMELY.blogsFolderPath"
    private let sidebarVisibleDefaultsKey = "HTTMELY.sidebarVisible"
    private let contentsVisibleDefaultsKey = "HTTMELY.contentsVisible"
    private let topBarVisibleDefaultsKey = "HTTMELY.topBarVisible"
    private let lastSourceModeDefaultsKey = "HTTMELY.lastSourceMode"
    private let windowFrameAutosaveName = NSWindow.FrameAutosaveName("HTTMELY.mainWindow")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        folderModes = loadSavedFolderModes()
        loadPersistedUIState()
        buildMenu()
        buildWindow()
        installKeyboardShortcuts()
        switchMode(restoredSourceMode())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else { return true }
        let hasSelectedReport = selectedReport != nil
        let hasReports = !currentItems.isEmpty
        let hasMultipleReports = currentItems.count > 1
        let hasCurrentFolder = currentReadRoot != nil
        let isFolderMode: Bool
        if case .folder = sourceMode {
            isFolderMode = true
        } else {
            isFolderMode = false
        }

        switch action {
        case #selector(openInBrowser), #selector(revealFile):
            return hasSelectedReport
        case #selector(openReportFromMenu(_:)), #selector(revealReportFromMenu(_:)):
            guard let id = menuItem.representedObject as? String else { return false }
            return currentItems.contains { $0.id == id }
        case #selector(revealCurrentFolder), #selector(exportCurrentFolder):
            return hasCurrentFolder
        case #selector(writeDatedArchiveCopy):
            return hasCurrentFolder && sourceMode != .welcome
        case #selector(selectPreviousReport), #selector(selectNextReport):
            return hasMultipleReports
        case #selector(reloadReport):
            return hasReports || hasCurrentFolder
        case #selector(renameCurrentFolderMode),
             #selector(moveCurrentFolderModeUp),
             #selector(moveCurrentFolderModeDown),
             #selector(moveCurrentFolderModeToTop),
             #selector(moveCurrentFolderModeToBottom),
             #selector(removeCurrentFolderMode):
            return isFolderMode
        case #selector(showFolderMode(_:)):
            guard let id = menuItem.representedObject as? String else { return false }
            return folderMode(withID: id) != nil
        default:
            return true
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    private func installKeyboardShortcuts() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event) ?? event
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCommandOption = flags.contains(.command) && flags.contains(.option)
        guard hasCommandOption else { return event }

        switch event.keyCode {
        case 123:
            selectPreviousFolderMode()
            return nil
        case 124:
            selectNextFolderMode()
            return nil
        case 126:
            if flags.contains(.shift) {
                moveCurrentFolderModeToTop()
            } else {
                moveCurrentFolderModeUp()
            }
            return nil
        case 125:
            if flags.contains(.shift) {
                moveCurrentFolderModeToBottom()
            } else {
                moveCurrentFolderModeDown()
            }
            return nil
        default:
            return event
        }
    }

    private func buildWindow() {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsMagnification = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.setValue(false, forKey: "drawsBackground")

        let sidebar = buildSidebar()
        appSidebar = sidebar
        let header = buildHeader()
        headerView = header
        header.isHidden = !isTopBarVisible
        headerHeightConstraint = header.heightAnchor.constraint(equalToConstant: isTopBarVisible ? 38 : 0)

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(header)
        content.addSubview(webView)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            header.topAnchor.constraint(equalTo: content.topAnchor),
            headerHeightConstraint,

            webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            webView.topAnchor.constraint(equalTo: header.bottomAnchor),
            webView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(sidebar)
        splitView.addArrangedSubview(content)

        sidebar.widthAnchor.constraint(equalToConstant: 230).isActive = true

        let root = NSView()
        root.addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: root.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1220, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = appDisplayName
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.minSize = NSSize(width: 900, height: 620)
        if !window.setFrameUsingName(windowFrameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(windowFrameAutosaveName)
        window.contentView = root
        appSidebar.isHidden = !isAppSidebarVisible
        splitView.adjustSubviews()
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        let about = NSMenuItem(title: "About \(appDisplayName)", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit \(appDisplayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")

        let openReport = NSMenuItem(title: "Open Selected Report", action: #selector(openInBrowser), keyEquivalent: "o")
        openReport.keyEquivalentModifierMask = [.command]
        openReport.target = self
        fileMenu.addItem(openReport)

        let revealReport = NSMenuItem(title: "Reveal Selected Report", action: #selector(revealFile), keyEquivalent: "")
        revealReport.target = self
        fileMenu.addItem(revealReport)

        let revealFolder = NSMenuItem(title: "Reveal Current Folder", action: #selector(revealCurrentFolder), keyEquivalent: "")
        revealFolder.target = self
        fileMenu.addItem(revealFolder)

        fileMenu.addItem(.separator())

        let exportFolder = NSMenuItem(title: "Export Current Folder...", action: #selector(exportCurrentFolder), keyEquivalent: "e")
        exportFolder.keyEquivalentModifierMask = [.command, .option]
        exportFolder.target = self
        fileMenu.addItem(exportFolder)

        let archiveFolder = NSMenuItem(title: "Write Archive Copy", action: #selector(writeDatedArchiveCopy), keyEquivalent: "a")
        archiveFolder.keyEquivalentModifierMask = [.command, .option]
        archiveFolder.target = self
        fileMenu.addItem(archiveFolder)

        fileMenuItem.submenu = fileMenu

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")

        let previousReport = NSMenuItem(title: "Previous Report", action: #selector(selectPreviousReport), keyEquivalent: "[")
        previousReport.keyEquivalentModifierMask = [.command]
        previousReport.target = self
        viewMenu.addItem(previousReport)

        let nextReport = NSMenuItem(title: "Next Report", action: #selector(selectNextReport), keyEquivalent: "]")
        nextReport.keyEquivalentModifierMask = [.command]
        nextReport.target = self
        viewMenu.addItem(nextReport)

        let reload = NSMenuItem(title: "Reload", action: #selector(reloadReport), keyEquivalent: "r")
        reload.keyEquivalentModifierMask = [.command]
        reload.target = self
        viewMenu.addItem(reload)

        viewMenu.addItem(.separator())

        let toggleAppSidebar = NSMenuItem(title: "Sidebar", action: #selector(toggleAppSidebar), keyEquivalent: "s")
        toggleAppSidebar.keyEquivalentModifierMask = [.command, .option]
        toggleAppSidebar.target = self
        viewMenu.addItem(toggleAppSidebar)

        let toggleContents = NSMenuItem(title: "Contents", action: #selector(toggleReportContentsSidebar), keyEquivalent: "c")
        toggleContents.keyEquivalentModifierMask = [.command, .option]
        toggleContents.target = self
        viewMenu.addItem(toggleContents)

        let toggleTopBar = NSMenuItem(title: "Title Bar", action: #selector(toggleTopBar), keyEquivalent: "t")
        toggleTopBar.keyEquivalentModifierMask = [.command, .option]
        toggleTopBar.target = self
        toggleTopBar.state = isTopBarVisible ? .on : .off
        topBarMenuItem = toggleTopBar
        viewMenu.addItem(toggleTopBar)

        viewMenuItem.submenu = viewMenu

        let placesMenuItem = NSMenuItem()
        mainMenu.addItem(placesMenuItem)
        let placesMenu = NSMenu(title: "Places")
        self.modeMenu = placesMenu
        rebuildModeMenuItems()
        placesMenuItem.submenu = placesMenu

        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "Help")

        let howToUse = NSMenuItem(title: "\(appDisplayName) Help", action: #selector(showHowToUse), keyEquivalent: "?")
        howToUse.keyEquivalentModifierMask = [.command]
        howToUse.target = self
        helpMenu.addItem(howToUse)

        let shortcuts = NSMenuItem(title: "Keyboard Shortcuts", action: #selector(showKeyboardShortcuts), keyEquivalent: "")
        shortcuts.target = self
        helpMenu.addItem(shortcuts)

        helpMenuItem.submenu = helpMenu
        NSApp.mainMenu = mainMenu
    }

    private func rebuildModeMenuItems() {
        guard let modeMenu else { return }

        modeMenu.removeAllItems()
        folderModeMenuItems.removeAll()

        let welcomeItem = NSMenuItem(title: "Welcome", action: #selector(showWelcomeMode), keyEquivalent: "1")
        welcomeItem.keyEquivalentModifierMask = [.command, .option]
        welcomeItem.target = self
        welcomeModeMenuItem = welcomeItem
        modeMenu.addItem(welcomeItem)

        let reportsItem = NSMenuItem(title: "Reports", action: #selector(showReportsMode), keyEquivalent: "2")
        reportsItem.keyEquivalentModifierMask = [.command, .option]
        reportsItem.target = self
        reportsModeMenuItem = reportsItem
        modeMenu.addItem(reportsItem)

        if !folderModes.isEmpty {
            modeMenu.addItem(.separator())
        }

        for (index, folderMode) in folderModes.enumerated() {
            let keyEquivalent = index < 7 ? "\(index + 3)" : ""
            let item = NSMenuItem(title: folderMode.title, action: #selector(showFolderMode(_:)), keyEquivalent: keyEquivalent)
            item.keyEquivalentModifierMask = keyEquivalent.isEmpty ? [] : [.command, .option]
            item.target = self
            item.representedObject = folderMode.id
            item.toolTip = folderMode.folderURL.path
            folderModeMenuItems[folderMode.id] = item
            modeMenu.addItem(item)
        }

        modeMenu.addItem(.separator())

        let addFolder = NSMenuItem(title: "Add Folder...", action: #selector(addFolderMode), keyEquivalent: "f")
        addFolder.keyEquivalentModifierMask = [.command, .option]
        addFolder.target = self
        modeMenu.addItem(addFolder)

        let managePlaces = NSMenuItem(title: "Manage Places...", action: #selector(showPlacesManager), keyEquivalent: ",")
        managePlaces.keyEquivalentModifierMask = [.command, .option]
        managePlaces.target = self
        modeMenu.addItem(managePlaces)

        modeMenu.addItem(.separator())

        let renameFolder = NSMenuItem(title: "Rename Current Place...", action: #selector(renameCurrentFolderMode), keyEquivalent: "n")
        renameFolder.keyEquivalentModifierMask = [.command, .option]
        renameFolder.target = self
        modeMenu.addItem(renameFolder)

        let revealFolder = NSMenuItem(title: "Reveal Current Folder", action: #selector(revealCurrentFolder), keyEquivalent: "")
        revealFolder.target = self
        modeMenu.addItem(revealFolder)

        let reorderItem = NSMenuItem(title: "Reorder Current Place", action: nil, keyEquivalent: "")
        let reorderMenu = NSMenu(title: "Reorder Current Place")

        let moveFolderUp = NSMenuItem(title: "Move Up", action: #selector(moveCurrentFolderModeUp), keyEquivalent: "\u{F700}")
        moveFolderUp.keyEquivalentModifierMask = [.command, .option]
        moveFolderUp.target = self
        reorderMenu.addItem(moveFolderUp)

        let moveFolderDown = NSMenuItem(title: "Move Down", action: #selector(moveCurrentFolderModeDown), keyEquivalent: "\u{F701}")
        moveFolderDown.keyEquivalentModifierMask = [.command, .option]
        moveFolderDown.target = self
        reorderMenu.addItem(moveFolderDown)

        reorderMenu.addItem(.separator())

        let moveFolderTop = NSMenuItem(title: "Move to First", action: #selector(moveCurrentFolderModeToTop), keyEquivalent: "\u{F700}")
        moveFolderTop.keyEquivalentModifierMask = [.command, .option, .shift]
        moveFolderTop.target = self
        reorderMenu.addItem(moveFolderTop)

        let moveFolderBottom = NSMenuItem(title: "Move to Last", action: #selector(moveCurrentFolderModeToBottom), keyEquivalent: "\u{F701}")
        moveFolderBottom.keyEquivalentModifierMask = [.command, .option, .shift]
        moveFolderBottom.target = self
        reorderMenu.addItem(moveFolderBottom)

        reorderItem.submenu = reorderMenu
        modeMenu.addItem(reorderItem)

        let removeFolder = NSMenuItem(title: "Remove Current Place", action: #selector(removeCurrentFolderMode), keyEquivalent: "\u{8}")
        removeFolder.keyEquivalentModifierMask = [.command, .option]
        removeFolder.target = self
        modeMenu.addItem(removeFolder)

        updateModeMenuState()
    }

    private func buildSidebar() -> NSView {
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 60, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        sidebarRootStack = stack

        sidebarTitleLabel = label("Reports", font: .systemFont(ofSize: 15, weight: .semibold), color: .labelColor)
        sidebarTitleLabel.isHidden = true
        sidebarSubtitleLabel = label("Generated local reports", font: .systemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)

        placesPopup = buildPlacesPopup()

        let placePickerContainer = NSView()
        placePickerContainer.translatesAutoresizingMaskIntoConstraints = false
        placePickerContainer.widthAnchor.constraint(equalToConstant: 202).isActive = true
        placePickerContainer.heightAnchor.constraint(equalToConstant: 24).isActive = true
        placePickerContainer.addSubview(placesPopup)
        NSLayoutConstraint.activate([
            placesPopup.leadingAnchor.constraint(equalTo: placePickerContainer.leadingAnchor, constant: -7),
            placesPopup.centerYAnchor.constraint(equalTo: placePickerContainer.centerYAnchor),
            placesPopup.widthAnchor.constraint(equalToConstant: 209)
        ])

        stack.addArrangedSubview(placePickerContainer)
        stack.setCustomSpacing(18, after: placePickerContainer)

        sidebarItemStack = NSStackView()
        sidebarItemStack.orientation = .vertical
        sidebarItemStack.alignment = .leading
        sidebarItemStack.spacing = 8
        sidebarItemStack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(sidebarItemStack)

        let sidebarFooter = buildSidebarFooterControls()
        sidebar.addSubview(stack)
        sidebar.addSubview(sidebarFooter)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            stack.topAnchor.constraint(equalTo: sidebar.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: sidebarFooter.topAnchor, constant: -12),

            sidebarFooter.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16),
            sidebarFooter.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -14)
        ])

        return sidebar
    }

    private func buildHeader() -> NSView {
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false

        let bottomRule = NSBox()
        bottomRule.boxType = .separator
        bottomRule.translatesAutoresizingMaskIntoConstraints = false

        titleLabel = label("", font: .systemFont(ofSize: 14, weight: .semibold), color: .labelColor)
        subtitleLabel = label("", font: .systemFont(ofSize: 10, weight: .regular), color: .tertiaryLabelColor)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let titleStack = NSStackView(views: [titleLabel, subtitleLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 3
        titleStack.translatesAutoresizingMaskIntoConstraints = false

        header.addSubview(titleStack)
        header.addSubview(bottomRule)

        NSLayoutConstraint.activate([
            titleStack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 18),
            titleStack.centerYAnchor.constraint(equalTo: header.centerYAnchor, constant: 3),
            titleStack.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -18),

            bottomRule.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            bottomRule.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            bottomRule.bottomAnchor.constraint(equalTo: header.bottomAnchor)
        ])

        return header
    }

    private func buildSidebarFooterControls() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let previousButton = headerButton(symbolName: "chevron.left", accessibilityLabel: "Previous Report", action: #selector(selectPreviousReport), size: 26, controlSize: .small)
        previousButton.toolTip = "Previous report (Command-[)"
        let nextButton = headerButton(symbolName: "chevron.right", accessibilityLabel: "Next Report", action: #selector(selectNextReport), size: 26, controlSize: .small)
        nextButton.toolTip = "Next report (Command-])"
        contentsButton = headerButton(symbolName: "sidebar.right", accessibilityLabel: "Report Contents", action: #selector(toggleReportContentsSidebar), size: 26, controlSize: .small)
        updateContentsButtonState()
        let reloadButton = headerButton(symbolName: "arrow.clockwise", accessibilityLabel: "Reload", action: #selector(reloadReport), size: 26, controlSize: .small)
        reloadButton.toolTip = "Reload report (Command-R)"

        let stack = NSStackView(views: [previousButton, nextButton, contentsButton!, reloadButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func buildPlacesPopup() -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.controlSize = .regular
        popup.bezelStyle = .shadowlessSquare
        popup.isBordered = false
        popup.font = .systemFont(ofSize: 13, weight: .semibold)
        popup.target = self
        popup.action = #selector(placesPopupChanged(_:))
        popup.toolTip = "Switch report folder"
        rebuildPlacesPopup(popup)
        return popup
    }

    private func resolveWelcomeRoot() -> URL {
        let fileManager = FileManager.default
        let environmentOverride = ProcessInfo.processInfo.environment["HTTMELY_WELCOME_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
        }
        let bundleWelcome = Bundle.main.resourceURL?
            .appendingPathComponent("Welcome", isDirectory: true)
            .standardizedFileURL
        let launchWelcome = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .standardizedFileURL
            .appendingPathComponent("Resources/Welcome", isDirectory: true)

        for candidate in [environmentOverride, bundleWelcome, launchWelcome].compactMap({ $0 }) {
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return bundleWelcome ?? launchWelcome
    }

    private func resolveReportRoot() -> URL {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        let environmentOverride = environment["HTTMELY_REPORTS_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
        let legacyOverride = environment["HTTMELY_LEGACY_REPORTS_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }

        let bundleRelativeReports = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("reports", isDirectory: true)

        let launchDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true).standardizedFileURL
        let launchRelativeReports = launchDirectory.appendingPathComponent("reports", isDirectory: true)
        let parentRelativeReports = launchDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("reports", isDirectory: true)

        for candidate in [
            environmentOverride,
            bundleRelativeReports,
            launchRelativeReports,
            parentRelativeReports,
            legacyOverride
        ].compactMap({ $0 }) {
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return bundleRelativeReports
    }

    private func resolveDefaultFolderRoot() -> URL {
        if let path = ProcessInfo.processInfo.environment["HTTMELY_DEFAULT_FOLDER_DIR"],
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        }

        return homeDirectory
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("HTTMELY Pages", isDirectory: true)
    }

    private func reportButton(_ report: Report) -> NSButton {
        let button = NSButton(title: report.title, target: self, action: #selector(reportButtonPressed(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(report.id)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 12.5, weight: .regular)
        if case .folder = sourceMode {
            button.cell?.lineBreakMode = .byTruncatingMiddle
        } else {
            button.cell?.lineBreakMode = .byTruncatingTail
        }
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        button.alignment = .left
        button.setButtonType(.toggle)
        button.widthAnchor.constraint(equalToConstant: 202).isActive = true
        button.toolTip = report.subtitle
        button.menu = reportContextMenu(for: report)
        styleReportButton(button, isSelected: false)
        return button
    }

    private func reportContextMenu(for report: Report) -> NSMenu {
        let menu = NSMenu()

        let open = NSMenuItem(title: "Open Externally", action: #selector(openReportFromMenu(_:)), keyEquivalent: "")
        open.target = self
        open.representedObject = report.id
        menu.addItem(open)

        let reveal = NSMenuItem(title: "Reveal File in Finder", action: #selector(revealReportFromMenu(_:)), keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = report.id
        menu.addItem(reveal)

        return menu
    }

    private func styleReportButton(_ button: NSButton, isSelected: Bool) {
        let title: String
        if let id = button.identifier?.rawValue,
           let reportTitle = currentItems.first(where: { $0.id == id })?.title {
            title = reportTitle
        } else {
            title = button.title
        }
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12.5, weight: isSelected ? .semibold : .regular),
                .foregroundColor: isSelected ? NSColor.labelColor : NSColor.secondaryLabelColor
            ]
        )
    }

    private func headerButton(
        symbolName: String,
        accessibilityLabel: String,
        action: Selector,
        size: CGFloat = 28,
        controlSize: NSControl.ControlSize = .regular
    ) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel) ?? NSImage(), target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.controlSize = controlSize
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel(accessibilityLabel)
        button.widthAnchor.constraint(equalToConstant: size).isActive = true
        button.heightAnchor.constraint(equalToConstant: size).isActive = true
        return button
    }

    private func groupLabel(_ title: String, width: CGFloat = 202) -> NSTextField {
        let field = label(title.uppercased(), font: .systemFont(ofSize: 10, weight: .semibold), color: .tertiaryLabelColor)
        field.maximumNumberOfLines = 1
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        return field
    }

    private func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.lineBreakMode = .byWordWrapping
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    private func builtInReportGroups() -> [ReportGroup] {
        [
            ReportGroup(title: "Scan", reports: [
                Report(
                    id: "applications",
                    title: "Applications",
                    subtitle: "/Applications audit and cleanup notes",
                    fileURL: reportRoot.appendingPathComponent("applications.html")
                ),
                Report(
                    id: "homebrew",
                    title: "Homebrew",
                    subtitle: "Casks, CLI tools, and support libraries",
                    fileURL: reportRoot.appendingPathComponent("homebrew.html")
                )
            ]),
            ReportGroup(title: "Review", reports: [
                Report(
                    id: "cleanup",
                    title: "Cleanup",
                    subtitle: "Keep, remove, duplicate, and review guidance",
                    fileURL: reportRoot.appendingPathComponent("cleanup.html")
                ),
                Report(
                    id: "stale-apps",
                    title: "Stale Apps",
                    subtitle: "Apps older than the 180-day review threshold",
                    fileURL: reportRoot.appendingPathComponent("stale_apps.html")
                ),
                Report(
                    id: "diskWeight",
                    title: "Disk Weight",
                    subtitle: "Largest apps and high-signal local folders",
                    fileURL: reportRoot.appendingPathComponent("disk_weight.html")
                )
            ]),
            ReportGroup(title: "System", reports: [
                Report(
                    id: "background",
                    title: "Background",
                    subtitle: "Menu bar, sync, VPN, clipboard, launcher, cleaner, automation, and always-on tools",
                    fileURL: reportRoot.appendingPathComponent("background.html")
                ),
                Report(
                    id: "startup",
                    title: "Startup",
                    subtitle: "LaunchAgents, LaunchDaemons, and startup-adjacent review",
                    fileURL: reportRoot.appendingPathComponent("startup.html")
                ),
                Report(
                    id: "developer-stack",
                    title: "Developer Stack",
                    subtitle: "Developer apps, runtimes, package managers, and CLIs",
                    fileURL: reportRoot.appendingPathComponent("developer_stack.html")
                ),
                Report(
                    id: "ai-tools",
                    title: "AI Tools",
                    subtitle: "AI assistants, local model tools, agents, and overlap guidance",
                    fileURL: reportRoot.appendingPathComponent("ai_tools.html")
                )
            ]),
            ReportGroup(title: "Project", reports: [
                Report(
                    id: "projects",
                    title: "Projects",
                    subtitle: "First-pass project inventory for later refinement",
                    fileURL: reportRoot.appendingPathComponent("projects.html")
                ),
                Report(
                    id: "index",
                    title: "Index",
                    subtitle: "Open the report landing page",
                    fileURL: reportRoot.appendingPathComponent("index.html")
                )
            ])
        ]
    }

    private func builtInReports() -> [Report] {
        builtInReportGroups().flatMap(\.reports)
    }

    private func loadSavedFolderModes() -> [FolderMode] {
        let storedValue = defaults.object(forKey: folderModesDefaultsKey)

        if let storedModes = storedValue as? [[String: String]] {
            return uniqueFolderModes(storedModes.compactMap { item in
                guard let path = item["path"] else { return nil }
                return folderMode(for: path, title: item["title"])
            })
        }

        let savedPaths: [String]
        if let storedPaths = storedValue as? [String] {
            savedPaths = storedPaths
        } else {
            var seededPaths: [String] = []
            if FileManager.default.fileExists(atPath: defaultBlogsRoot.path) {
                seededPaths.append(defaultBlogsRoot.path)
            }
            for legacyKey in [folderDefaultsKey, legacyBlogsFolderDefaultsKey] {
                if let legacyPath = defaults.string(forKey: legacyKey),
                   !legacyPath.isEmpty,
                   !seededPaths.contains(legacyPath) {
                    seededPaths.append(legacyPath)
                }
            }
            savedPaths = seededPaths
        }

        return uniqueFolderModes(savedPaths.map { folderMode(for: $0) })
    }

    private func loadPersistedUIState() {
        if defaults.object(forKey: sidebarVisibleDefaultsKey) != nil {
            isAppSidebarVisible = defaults.bool(forKey: sidebarVisibleDefaultsKey)
        }
        if defaults.object(forKey: contentsVisibleDefaultsKey) != nil {
            isReportContentsVisible = defaults.bool(forKey: contentsVisibleDefaultsKey)
        }
        if defaults.object(forKey: topBarVisibleDefaultsKey) != nil {
            isTopBarVisible = defaults.bool(forKey: topBarVisibleDefaultsKey)
        }
    }

    private func restoredSourceMode() -> SourceMode {
        guard let storedMode = defaults.string(forKey: lastSourceModeDefaultsKey) else {
            return .welcome
        }
        if storedMode == "welcome" {
            return .welcome
        }
        if storedMode == "reports" {
            return .reports
        }
        if folderMode(withID: storedMode) != nil {
            return .folder(storedMode)
        }
        return .welcome
    }

    private func persistSourceMode() {
        switch sourceMode {
        case .welcome:
            defaults.set("welcome", forKey: lastSourceModeDefaultsKey)
        case .reports:
            defaults.set("reports", forKey: lastSourceModeDefaultsKey)
        case .folder(let id):
            defaults.set(id, forKey: lastSourceModeDefaultsKey)
        }
    }

    private func uniqueFolderModes(_ modes: [FolderMode]) -> [FolderMode] {
        var seen: Set<String> = []
        var unique: [FolderMode] = []

        for mode in modes {
            let standardizedPath = mode.folderURL.standardizedFileURL.path
            guard !seen.contains(standardizedPath) else { continue }
            seen.insert(standardizedPath)
            unique.append(mode)
        }

        return unique
    }

    private func folderMode(for path: String, title: String? = nil) -> FolderMode {
        let folderURL = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return FolderMode(
            id: folderURL.path,
            folderURL: folderURL,
            title: trimmedTitle?.isEmpty == false ? trimmedTitle! : folderModeName(for: folderURL)
        )
    }

    private func saveFolderModes() {
        let storedModes = folderModes.map { mode in
            [
                "path": mode.folderURL.path,
                "title": mode.title
            ]
        }
        defaults.set(storedModes, forKey: folderModesDefaultsKey)
    }

    private func folderMode(withID id: String) -> FolderMode? {
        folderModes.first { $0.id == id }
    }

    private func currentModeTitle() -> String {
        switch sourceMode {
        case .welcome:
            return "Welcome"
        case .reports:
            return "Reports"
        case .folder(let id):
            return folderMode(withID: id)?.title ?? folderModeName(for: currentReadRoot ?? defaultBlogsRoot)
        }
    }

    private func currentModeSubtitle() -> String {
        switch sourceMode {
        case .welcome:
            return "Start here"
        case .reports:
            return "Generated local reports"
        case .folder(let id):
            return folderMode(withID: id)?.subtitle ?? "Folder HTML/Markdown viewer"
        }
    }

    private func folderModeName(for folderURL: URL) -> String {
        let rawName = folderURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawName.lowercased() == "blog" || rawName.lowercased() == "blogs" {
            return "Blogs"
        }

        let spaced = rawName
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return spaced.isEmpty ? "Folder" : spaced.capitalized
    }

    private func loadCurrentModeItems() {
        switch sourceMode {
        case .welcome:
            currentReadRoot = welcomeRoot
            currentItems = welcomeDocuments()
        case .reports:
            currentReadRoot = reportRoot
            currentItems = builtInReports()
        case .folder(let id):
            let mode = folderMode(withID: id) ?? folderModes.first
            currentReadRoot = mode?.folderURL ?? defaultBlogsRoot
            currentItems = folderDocuments(in: currentReadRoot).map { fileURL in
                Report(
                    id: "folder-\(fileURL.path)",
                    title: documentTitle(for: fileURL),
                    subtitle: relativePath(from: currentReadRoot, to: fileURL),
                    fileURL: fileURL
                )
            }
        }
    }

    private func welcomeDocuments() -> [Report] {
        [
            Report(id: "welcome", title: "Welcome", subtitle: "Start here", fileURL: welcomeRoot.appendingPathComponent("00-welcome.html")),
            Report(id: "how-to", title: "How To", subtitle: "Basic workflow", fileURL: welcomeRoot.appendingPathComponent("01-how-to.html")),
            Report(id: "create-pages", title: "Create Pages", subtitle: "Make folders HTTMELY can read", fileURL: welcomeRoot.appendingPathComponent("02-create-pages.html")),
            Report(id: "use-cases", title: "Use Cases", subtitle: "Blogs, reports, archives, and project packets", fileURL: welcomeRoot.appendingPathComponent("03-use-cases.html")),
            Report(id: "daily-reports", title: "Daily Reports", subtitle: "Notes, apps, agents, and exports", fileURL: welcomeRoot.appendingPathComponent("04-daily-reports.html")),
            Report(id: "saved-sites", title: "Saved Sites", subtitle: "SingleFile and offline web archives", fileURL: welcomeRoot.appendingPathComponent("05-saved-sites.html")),
            Report(id: "design-md", title: "Design.md", subtitle: "Design-system research collections", fileURL: welcomeRoot.appendingPathComponent("06-design-md.html")),
            Report(id: "about", title: "About", subtitle: "What HTTMELY is for", fileURL: welcomeRoot.appendingPathComponent("07-about.html")),
            Report(id: "contact", title: "Contact", subtitle: "Support notes", fileURL: welcomeRoot.appendingPathComponent("08-contact.html")),
            Report(id: "privacy", title: "Privacy", subtitle: "Local-first behavior", fileURL: welcomeRoot.appendingPathComponent("09-privacy.html"))
        ]
    }

    private func folderDocuments(in root: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else {
            return []
        }

        let files = enumerator.compactMap { item -> URL? in
            guard let fileURL = item as? URL else { return nil }
            let pathExtension = fileURL.pathExtension.lowercased()
            guard ["html", "htm", "md", "markdown"].contains(pathExtension) else { return nil }
            return fileURL
        }

        return files.sorted { first, second in
            let firstDate = (try? first.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let secondDate = (try? second.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if firstDate != secondDate {
                return firstDate > secondDate
            }
            return first.path.localizedStandardCompare(second.path) == .orderedAscending
        }
    }

    private func documentTitle(for fileURL: URL) -> String {
        let pathExtension = fileURL.pathExtension.lowercased()
        if pathExtension == "md" || pathExtension == "markdown" {
            return markdownTitle(for: fileURL)
        }
        return htmlTitle(for: fileURL)
    }

    private func htmlTitle(for fileURL: URL) -> String {
        let fallback = fallbackTitle(for: fileURL)
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
              let source = String(data: Data(data.prefix(160_000)), encoding: .utf8) else {
            return fallback
        }

        let lowercased = source.lowercased()
        guard let startRange = lowercased.range(of: "<title>"),
              let endRange = lowercased.range(of: "</title>", range: startRange.upperBound..<lowercased.endIndex) else {
            return fallback
        }

        let title = source[startRange.upperBound..<endRange.lowerBound]
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return title.isEmpty ? fallback : decodeCommonEntities(title)
    }

    private func markdownTitle(for fileURL: URL) -> String {
        guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return fallbackTitle(for: fileURL)
        }

        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }

        return fallbackTitle(for: fileURL)
    }

    private func fallbackTitle(for fileURL: URL) -> String {
        if fileURL.lastPathComponent.lowercased().hasPrefix("index.") {
            return fileURL.deletingLastPathComponent().lastPathComponent
        }

        return fileURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func decodeCommonEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private func relativePath(from root: URL, to fileURL: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        if filePath.hasPrefix(rootPath + "/") {
            return String(filePath.dropFirst(rootPath.count + 1))
        }
        return fileURL.lastPathComponent
    }

    private func switchMode(_ mode: SourceMode) {
        sourceMode = mode
        persistSourceMode()
        loadCurrentModeItems()
        updateModeMenuState()
        updateSidebarHeader()
        updateContentsButtonState()
        rebuildSidebarItems()

        if let firstReport = currentItems.first {
            selectReport(firstReport)
        } else {
            selectedReport = nil
            titleLabel.stringValue = currentModeTitle()
            subtitleLabel.stringValue = currentReadRoot.path
            loadEmptyModePage()
        }
    }

    private func updateModeMenuState() {
        welcomeModeMenuItem?.state = sourceMode == .welcome ? .on : .off
        reportsModeMenuItem?.state = sourceMode == .reports ? .on : .off

        for (id, item) in folderModeMenuItems {
            item.state = sourceMode == .folder(id) ? .on : .off
        }

        guard placesPopup != nil else { return }
        let selectedID: String
        switch sourceMode {
        case .welcome:
            selectedID = "welcome"
        case .reports:
            selectedID = "reports"
        case .folder(let id):
            selectedID = id
        }

        if let item = placesPopup.itemArray.first(where: { ($0.representedObject as? String) == selectedID }) {
            placesPopup.select(item)
        }
    }

    private func updateSidebarHeader() {
        sidebarTitleLabel.stringValue = currentModeTitle()
        sidebarSubtitleLabel.stringValue = currentModeSubtitle()
        let currentFolderMode: FolderMode?
        if case .folder = sourceMode {
            sidebarSubtitleLabel.toolTip = currentReadRoot.path
            if case .folder(let id) = sourceMode {
                currentFolderMode = folderMode(withID: id)
            } else {
                currentFolderMode = nil
            }
        } else {
            sidebarSubtitleLabel.toolTip = nil
            currentFolderMode = nil
        }
        updateFolderInlineControls(for: currentFolderMode)
        sidebarRootStack.edgeInsets = NSEdgeInsets(top: 60, left: 16, bottom: 16, right: 12)
        sidebarItemStack.spacing = 5
    }

    private func updateFolderInlineControls(for mode: FolderMode?) {
        let hasFolderMode = mode != nil

        let contextMenu = hasFolderMode ? currentFolderContextMenu() : reportsPlaceContextMenu()
        sidebarTitleLabel.menu = contextMenu
        sidebarSubtitleLabel.menu = contextMenu
    }

    private func currentFolderContextMenu() -> NSMenu {
        let menu = NSMenu()

        let add = NSMenuItem(title: "Add Folder...", action: #selector(addFolderMode), keyEquivalent: "")
        add.target = self
        menu.addItem(add)

        let manage = NSMenuItem(title: "Manage Places...", action: #selector(showPlacesManager), keyEquivalent: "")
        manage.target = self
        menu.addItem(manage)

        menu.addItem(.separator())

        let rename = NSMenuItem(title: "Rename Place...", action: #selector(renameCurrentFolderMode), keyEquivalent: "")
        rename.target = self
        menu.addItem(rename)

        let reveal = NSMenuItem(title: "Reveal Folder in Finder", action: #selector(revealCurrentFolder), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)

        menu.addItem(.separator())

        let moveUp = NSMenuItem(title: "Move Up", action: #selector(moveCurrentFolderModeUp), keyEquivalent: "")
        moveUp.target = self
        menu.addItem(moveUp)

        let moveDown = NSMenuItem(title: "Move Down", action: #selector(moveCurrentFolderModeDown), keyEquivalent: "")
        moveDown.target = self
        menu.addItem(moveDown)

        let moveTop = NSMenuItem(title: "Move to First", action: #selector(moveCurrentFolderModeToTop), keyEquivalent: "")
        moveTop.target = self
        menu.addItem(moveTop)

        let moveBottom = NSMenuItem(title: "Move to Last", action: #selector(moveCurrentFolderModeToBottom), keyEquivalent: "")
        moveBottom.target = self
        menu.addItem(moveBottom)

        menu.addItem(.separator())

        let remove = NSMenuItem(title: "Remove from Places", action: #selector(removeCurrentFolderMode), keyEquivalent: "")
        remove.target = self
        menu.addItem(remove)

        return menu
    }

    private func reportsPlaceContextMenu() -> NSMenu {
        let menu = NSMenu()

        let add = NSMenuItem(title: "Add Folder...", action: #selector(addFolderMode), keyEquivalent: "")
        add.target = self
        menu.addItem(add)

        let manage = NSMenuItem(title: "Manage Places...", action: #selector(showPlacesManager), keyEquivalent: "")
        manage.target = self
        menu.addItem(manage)

        let reveal = NSMenuItem(title: "Reveal Reports Folder", action: #selector(revealCurrentFolder), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)

        return menu
    }

    private func currentPlacePopupMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let welcomeItem = NSMenuItem(title: "Welcome", action: #selector(showWelcomeMode), keyEquivalent: "")
        welcomeItem.target = self
        welcomeItem.representedObject = "welcome"
        welcomeItem.toolTip = "Start here"
        menu.addItem(welcomeItem)

        let reportsItem = NSMenuItem(title: "Reports", action: #selector(showReportsMode), keyEquivalent: "")
        reportsItem.target = self
        reportsItem.representedObject = "reports"
        reportsItem.toolTip = "Generated reports"
        menu.addItem(reportsItem)

        if !folderModes.isEmpty {
            menu.addItem(.separator())
        }

        for (index, mode) in folderModes.enumerated() {
            let item = NSMenuItem(title: mode.title, action: #selector(showFolderMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.id
            if index < 7 {
                item.toolTip = "\(mode.folderURL.path)\nCommand-Option-\(index + 3)"
            } else {
                item.toolTip = mode.folderURL.path
            }
            menu.addItem(item)
        }

        return menu
    }

    private func rebuildPlacesPopup(_ popup: NSPopUpButton? = nil) {
        let targetPopup = popup ?? placesPopup
        guard let targetPopup else { return }

        targetPopup.removeAllItems()

        targetPopup.addItem(withTitle: "Welcome")
        targetPopup.lastItem?.representedObject = "welcome"
        targetPopup.lastItem?.toolTip = "Start here"

        targetPopup.addItem(withTitle: "Reports")
        targetPopup.lastItem?.representedObject = "reports"
        targetPopup.lastItem?.toolTip = "Generated reports"

        if !folderModes.isEmpty {
            targetPopup.menu?.addItem(.separator())
        }

        for (index, mode) in folderModes.enumerated() {
            targetPopup.addItem(withTitle: mode.title)
            targetPopup.lastItem?.representedObject = mode.id
            if index < 7 {
                targetPopup.lastItem?.toolTip = "\(mode.folderURL.path)\nCommand-Option-\(index + 3)"
            } else {
                targetPopup.lastItem?.toolTip = mode.folderURL.path
            }
        }

        updateModeMenuState()
    }

    private func rebuildSidebarItems() {
        for view in sidebarItemStack.arrangedSubviews {
            sidebarItemStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        sidebarButtons.removeAll()

        if currentItems.isEmpty {
            let isFolderMode: Bool
            if case .folder = sourceMode {
                isFolderMode = true
            } else {
                isFolderMode = false
            }
            let emptyLabel = label(
                isFolderMode ? "No HTML or Markdown files found in this folder." : "No pages found.",
                font: .systemFont(ofSize: 12, weight: .regular),
                color: .secondaryLabelColor
            )
            emptyLabel.maximumNumberOfLines = 2
            emptyLabel.widthAnchor.constraint(equalToConstant: 202).isActive = true
            sidebarItemStack.addArrangedSubview(emptyLabel)

            if isFolderMode {
                let chooseButton = NSButton(title: "Add Folder", target: self, action: #selector(addFolderMode))
                chooseButton.bezelStyle = .rounded
                chooseButton.controlSize = .regular
                chooseButton.translatesAutoresizingMaskIntoConstraints = false
                chooseButton.widthAnchor.constraint(equalToConstant: 202).isActive = true
                sidebarItemStack.addArrangedSubview(chooseButton)
            }
            return
        }

        if sourceMode == .reports {
            for (index, group) in builtInReportGroups().enumerated() {
                if index > 0 {
                    sidebarItemStack.setCustomSpacing(10, after: sidebarItemStack.arrangedSubviews.last!)
                }
                let heading = groupLabel(group.title)
                sidebarItemStack.addArrangedSubview(heading)
                sidebarItemStack.setCustomSpacing(4, after: heading)

                for report in group.reports {
                    let button = reportButton(report)
                    sidebarButtons[report.id] = button
                    sidebarItemStack.addArrangedSubview(button)
                }
            }
        } else {
            for report in currentItems {
                let button = reportButton(report)
                sidebarButtons[report.id] = button
                sidebarItemStack.addArrangedSubview(button)
            }
        }
    }

    @objc private func showWelcomeMode() {
        switchMode(.welcome)
    }

    @objc private func showReportsMode() {
        switchMode(.reports)
    }

    @objc private func showFolderMode(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        switchMode(.folder(id))
    }

    @objc private func placesPopupChanged(_ sender: NSPopUpButton) {
        guard let id = sender.selectedItem?.representedObject as? String else { return }
        if id == "welcome" {
            switchMode(.welcome)
        } else if id == "reports" {
            switchMode(.reports)
        } else {
            switchMode(.folder(id))
        }
    }

    @objc private func showPlacesManager() {
        if let placesManagerWindow {
            window.beginSheet(placesManagerWindow)
            return
        }

        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 438),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        sheet.title = "Manage Places"

        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = label("Manage Places", font: .systemFont(ofSize: 17, weight: .semibold), color: .labelColor)
        let subtitle = label("These are saved local folder shortcuts. Their order controls the Places menu and header picker.", font: .systemFont(ofSize: 12, weight: .regular), color: .secondaryLabelColor)
        subtitle.maximumNumberOfLines = 2

        let tableView = NSTableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.rowHeight = 32
        tableView.delegate = self
        tableView.dataSource = self
        tableView.allowsMultipleSelection = false
        tableView.target = self
        tableView.doubleAction = #selector(renameSelectedPlaceFromManager)

        let orderColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("order"))
        orderColumn.title = ""
        orderColumn.width = 44
        orderColumn.minWidth = 44
        orderColumn.maxWidth = 44
        tableView.addTableColumn(orderColumn)

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Place"
        nameColumn.width = 190
        tableView.addTableColumn(nameColumn)

        let pathColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        pathColumn.title = "Folder"
        pathColumn.width = 410
        tableView.addTableColumn(pathColumn)
        placesManagerTableView = tableView

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = tableView

        let addButton = sheetButton("Add Folder...", action: #selector(addPlaceFromManager))
        let renameButton = sheetButton("Rename", action: #selector(renameSelectedPlaceFromManager))
        let removeButton = sheetButton("Remove from Places", action: #selector(removeSelectedPlaceFromManager))
        let topButton = sheetButton("First", action: #selector(moveSelectedPlaceToTop))
        let upButton = sheetButton("Up", action: #selector(moveSelectedPlaceUp))
        let downButton = sheetButton("Down", action: #selector(moveSelectedPlaceDown))
        let bottomButton = sheetButton("Last", action: #selector(moveSelectedPlaceToBottom))
        let doneButton = sheetButton("Done", action: #selector(closePlacesManager))
        doneButton.keyEquivalent = "\r"
        placesManagerActionButtons = [renameButton, removeButton, topButton, upButton, downButton, bottomButton]

        renameButton.toolTip = "Rename the selected place. This does not rename the folder on disk."
        removeButton.toolTip = "Remove the shortcut from HTTMELY. Files on disk are not deleted."
        topButton.toolTip = "Move selected place to the top"
        upButton.toolTip = "Move selected place up"
        downButton.toolTip = "Move selected place down"
        bottomButton.toolTip = "Move selected place to the bottom"

        let editControls = NSStackView(views: [addButton, renameButton, removeButton])
        editControls.orientation = .horizontal
        editControls.spacing = 8
        editControls.translatesAutoresizingMaskIntoConstraints = false

        let orderControls = NSStackView(views: [topButton, upButton, downButton, bottomButton])
        orderControls.orientation = .horizontal
        orderControls.spacing = 8
        orderControls.translatesAutoresizingMaskIntoConstraints = false

        let footer = label("Double-click a place to rename it. Remove from Places never deletes the real folder.", font: .systemFont(ofSize: 11, weight: .regular), color: .tertiaryLabelColor)
        footer.maximumNumberOfLines = 1

        root.addSubview(title)
        root.addSubview(subtitle)
        root.addSubview(scrollView)
        root.addSubview(editControls)
        root.addSubview(orderControls)
        root.addSubview(footer)
        root.addSubview(doneButton)
        sheet.contentView = root

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            title.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),

            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),

            scrollView.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 16),
            scrollView.heightAnchor.constraint(equalToConstant: 244),

            editControls.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            editControls.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 14),

            orderControls.leadingAnchor.constraint(greaterThanOrEqualTo: editControls.trailingAnchor, constant: 16),
            orderControls.trailingAnchor.constraint(lessThanOrEqualTo: doneButton.leadingAnchor, constant: -12),
            orderControls.centerYAnchor.constraint(equalTo: editControls.centerYAnchor),

            doneButton.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            doneButton.centerYAnchor.constraint(equalTo: editControls.centerYAnchor),

            footer.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            footer.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.trailingAnchor),
            footer.topAnchor.constraint(equalTo: editControls.bottomAnchor, constant: 12)
        ])

        placesManagerWindow = sheet
        refreshPlacesManagerSelection()
        window.beginSheet(sheet)
    }

    private func sheetButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .regular
        return button
    }

    @objc private func closePlacesManager() {
        guard let placesManagerWindow else { return }
        window.endSheet(placesManagerWindow)
        self.placesManagerWindow = nil
        placesManagerTableView = nil
        placesManagerActionButtons = []
    }

    @objc private func addPlaceFromManager() {
        addFolderMode()
        placesManagerTableView?.reloadData()
        refreshPlacesManagerSelection()
    }

    @objc private func renameSelectedPlaceFromManager() {
        guard let index = selectedManagedFolderIndex() else { return }
        renameFolderMode(at: index)
    }

    @objc private func removeSelectedPlaceFromManager() {
        guard let index = selectedManagedFolderIndex() else { return }
        removeFolderMode(at: index)
    }

    @objc private func moveSelectedPlaceUp() {
        moveSelectedManagedPlace(to: .relative(-1))
    }

    @objc private func moveSelectedPlaceDown() {
        moveSelectedManagedPlace(to: .relative(1))
    }

    @objc private func moveSelectedPlaceToTop() {
        moveSelectedManagedPlace(to: .absolute(0))
    }

    @objc private func moveSelectedPlaceToBottom() {
        moveSelectedManagedPlace(to: .absolute(max(folderModes.count - 1, 0)))
    }

    @objc private func addFolderMode() {
        let panel = NSOpenPanel()
        panel.title = "Add Folder"
        panel.message = "Pick one or more local folders that contain HTML or Markdown files. Each folder will be added as a place."
        panel.prompt = "Add"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = currentReadRoot ?? defaultBlogsRoot

        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        let existingIDs = Set(folderModes.map(\.id))
        let newModes = panel.urls
            .map { folderMode(for: $0.path) }
            .filter { !existingIDs.contains($0.id) }

        guard !newModes.isEmpty else {
            if let firstURL = panel.urls.first {
                switchMode(.folder(firstURL.standardizedFileURL.path))
            }
            return
        }

        folderModes.append(contentsOf: newModes)
        saveFolderModes()
        rebuildModeMenuItems()
        rebuildPlacesPopup()
        placesManagerTableView?.reloadData()
        switchMode(.folder(newModes[0].id))
    }

    @objc private func renameCurrentFolderMode() {
        guard case .folder(let id) = sourceMode,
              let index = folderModes.firstIndex(where: { $0.id == id }) else {
            showAlert(title: "No folder mode selected", message: "Switch to a folder mode before renaming it.")
            return
        }

        renameFolderMode(at: index)
    }

    private func renameFolderMode(at index: Int) {
        let mode = folderModes[index]
        let input = NSTextField(string: mode.title)
        input.frame = NSRect(x: 0, y: 0, width: 280, height: 24)

        let alert = NSAlert()
        alert.messageText = "Rename folder"
        alert.informativeText = "This changes the name shown in HTTMELY only. The folder on disk is not renamed.\n\n\(mode.folderURL.path)"
        alert.accessoryView = input
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newTitle = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty else { return }

        folderModes[index].title = newTitle
        saveFolderModes()
        rebuildModeMenuItems()
        rebuildPlacesPopup()
        placesManagerTableView?.reloadData()
        placesManagerTableView?.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        if sourceMode == .folder(mode.id) {
            switchMode(.folder(mode.id))
        }
    }

    @objc private func selectPreviousFolderMode() {
        selectAdjacentFolderMode(offset: -1)
    }

    @objc private func selectNextFolderMode() {
        selectAdjacentFolderMode(offset: 1)
    }

    private func selectAdjacentFolderMode(offset: Int) {
        guard !folderModes.isEmpty else { return }
        let currentIndex: Int
        if case .folder(let id) = sourceMode,
           let index = folderModes.firstIndex(where: { $0.id == id }) {
            currentIndex = index
        } else {
            currentIndex = offset > 0 ? -1 : 0
        }

        let nextIndex = (currentIndex + offset + folderModes.count) % folderModes.count
        switchMode(.folder(folderModes[nextIndex].id))
    }

    @objc private func moveCurrentFolderModeUp() {
        moveCurrentFolderMode(to: .relative(-1))
    }

    @objc private func moveCurrentFolderModeDown() {
        moveCurrentFolderMode(to: .relative(1))
    }

    @objc private func moveCurrentFolderModeToTop() {
        moveCurrentFolderMode(to: .absolute(0))
    }

    @objc private func moveCurrentFolderModeToBottom() {
        moveCurrentFolderMode(to: .absolute(max(folderModes.count - 1, 0)))
    }

    private enum FolderMoveTarget {
        case relative(Int)
        case absolute(Int)
    }

    private func moveCurrentFolderMode(to target: FolderMoveTarget) {
        guard case .folder(let id) = sourceMode,
              let index = folderModes.firstIndex(where: { $0.id == id }) else {
            showAlert(title: "No folder mode selected", message: "Switch to a folder mode before moving it.")
            return
        }

        let destination: Int
        switch target {
        case .relative(let offset):
            destination = min(max(index + offset, 0), folderModes.count - 1)
        case .absolute(let targetIndex):
            destination = min(max(targetIndex, 0), folderModes.count - 1)
        }

        guard destination != index else { return }
        let mode = folderModes.remove(at: index)
        folderModes.insert(mode, at: destination)
        commitFolderModeChanges(selectedIndex: destination)
        switchMode(.folder(id))
    }

    private func moveSelectedManagedPlace(to target: FolderMoveTarget) {
        guard let index = selectedManagedFolderIndex() else { return }
        let destination: Int
        switch target {
        case .relative(let offset):
            destination = min(max(index + offset, 0), folderModes.count - 1)
        case .absolute(let targetIndex):
            destination = min(max(targetIndex, 0), folderModes.count - 1)
        }

        guard destination != index else { return }
        let mode = folderModes.remove(at: index)
        folderModes.insert(mode, at: destination)
        commitFolderModeChanges(selectedIndex: destination)
    }

    @objc private func removeCurrentFolderMode() {
        guard case .folder(let id) = sourceMode,
              let index = folderModes.firstIndex(where: { $0.id == id }) else {
            showAlert(title: "No folder mode selected", message: "Switch to a folder mode before removing it.")
            return
        }

        removeFolderMode(at: index)
    }

    private func removeFolderMode(at index: Int) {
        let removedMode = folderModes[index]
        let alert = NSAlert()
        alert.messageText = "Remove folder mode?"
        alert.informativeText = "This only removes \(removedMode.title) from HTTMELY's Places menu. It does not delete files.\n\n\(removedMode.folderURL.path)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        folderModes.remove(at: index)
        commitFolderModeChanges(selectedIndex: min(index, folderModes.count - 1))

        if sourceMode == .folder(removedMode.id), !folderModes.isEmpty {
            let nextIndex = min(index, folderModes.count - 1)
            switchMode(.folder(folderModes[nextIndex].id))
        } else if sourceMode == .folder(removedMode.id) {
            switchMode(.welcome)
        }
    }

    private func commitFolderModeChanges(selectedIndex: Int? = nil) {
        saveFolderModes()
        rebuildModeMenuItems()
        rebuildPlacesPopup()
        placesManagerTableView?.reloadData()
        if let selectedIndex, selectedIndex >= 0, selectedIndex < folderModes.count {
            placesManagerTableView?.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
            placesManagerTableView?.scrollRowToVisible(selectedIndex)
            updatePlacesManagerControls()
        } else {
            refreshPlacesManagerSelection()
        }
    }

    private func selectedManagedFolderIndex() -> Int? {
        guard let tableView = placesManagerTableView else { return nil }
        let row = tableView.selectedRow
        guard row >= 0, row < folderModes.count else { return nil }
        return row
    }

    private func refreshPlacesManagerSelection() {
        guard let tableView = placesManagerTableView else { return }
        tableView.reloadData()
        if case .folder(let id) = sourceMode,
           let index = folderModes.firstIndex(where: { $0.id == id }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            tableView.scrollRowToVisible(index)
        } else if !folderModes.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        updatePlacesManagerControls()
    }

    private func updatePlacesManagerControls() {
        guard let tableView = placesManagerTableView else { return }
        let hasSelection = tableView.selectedRow >= 0 && tableView.selectedRow < folderModes.count
        for button in placesManagerActionButtons {
            button.isEnabled = hasSelection
        }
    }

    @objc private func reportButtonPressed(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let report = currentItems.first(where: { $0.id == id }) else {
            return
        }
        selectReport(report)
    }

    private func selectReport(_ report: Report) {
        selectedReport = report
        titleLabel.stringValue = report.title
        subtitleLabel.stringValue = report.fileURL.lastPathComponent
        subtitleLabel.toolTip = report.fileURL.path
        window.title = "\(appDisplayName) - \(report.title)"

        for (id, button) in sidebarButtons {
            let isSelected = id == report.id
            button.state = isSelected ? .on : .off
            styleReportButton(button, isSelected: isSelected)
        }

        if case .folder = sourceMode {
            loadFolderHTML(report)
        } else if FileManager.default.fileExists(atPath: report.fileURL.path) {
            webView.loadFileURL(report.fileURL, allowingReadAccessTo: currentReadRoot)
        } else {
            loadMissingReportPage(report)
        }
    }

    @objc private func selectPreviousReport() {
        selectAdjacentReport(offset: -1)
    }

    @objc private func selectNextReport() {
        selectAdjacentReport(offset: 1)
    }

    private func selectAdjacentReport(offset: Int) {
        guard !currentItems.isEmpty else { return }
        let currentIndex = selectedReport.flatMap { selected in
            currentItems.firstIndex { $0.id == selected.id }
        } ?? 0
        let nextIndex = (currentIndex + offset + currentItems.count) % currentItems.count
        selectReport(currentItems[nextIndex])
    }

    private func loadFolderHTML(_ report: Report) {
        guard FileManager.default.fileExists(atPath: report.fileURL.path),
              let source = try? String(contentsOf: report.fileURL, encoding: .utf8) else {
            loadMissingReportPage(report)
            return
        }

        let pathExtension = report.fileURL.pathExtension.lowercased()
        if pathExtension == "md" || pathExtension == "markdown" {
            webView.loadHTMLString(markdownPreviewHTML(source, title: report.title), baseURL: report.fileURL.deletingLastPathComponent())
        } else {
            let html = folderReaderHTML(
                normalizeLocalAssets(in: stripLocalRedirect(from: source), relativeTo: report.fileURL.deletingLastPathComponent())
            )
            loadGeneratedHTMLFile(html, namedFor: report)
        }
    }

    private func loadGeneratedHTMLFile(_ html: String, namedFor report: Report) {
        let cacheBase = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? homeDirectory.appendingPathComponent("Library/Caches", isDirectory: true)
        let cacheRoot = cacheBase.appendingPathComponent(appDisplayName, isDirectory: true)
        let fileName = String(report.fileURL.path.hashValue)
            .replacingOccurrences(of: "-", with: "n") + ".html"
        let fileURL = cacheRoot.appendingPathComponent(fileName)

        do {
            try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
            try html.write(to: fileURL, atomically: true, encoding: .utf8)
            webView.loadFileURL(fileURL, allowingReadAccessTo: homeDirectory)
        } catch {
            webView.loadHTMLString(html, baseURL: report.fileURL.deletingLastPathComponent())
        }
    }

    private func stripLocalRedirect(from html: String) -> String {
        let pattern = #"(?is)<script[^>]*>\s*window\.location\.(replace|href)\s*(\(|=)\s*['"][^'"]+['"]\)?;?\s*</script>"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return html }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return expression.stringByReplacingMatches(in: html, range: range, withTemplate: "")
    }

    private func normalizeLocalAssets(in html: String, relativeTo baseURL: URL) -> String {
        var output = html
        let attributes = ["src", "href", "poster"]

        for attribute in attributes {
            let pattern = #"(?i)\b\#(attribute)\s*=\s*["']([^"']+)["']"#
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = expression.matches(in: output, range: NSRange(output.startIndex..<output.endIndex, in: output)).reversed()

            for match in matches {
                guard match.numberOfRanges == 2,
                      let fullRange = Range(match.range(at: 0), in: output),
                      let valueRange = Range(match.range(at: 1), in: output) else {
                    continue
                }

                let rawValue = String(output[valueRange])
                guard let resolved = resolveLocalAsset(rawValue, relativeTo: baseURL) else { continue }
                output.replaceSubrange(fullRange, with: "\(attribute)=\"\(resolved.absoluteString)\"")
            }
        }

        return output
    }

    private func resolveLocalAsset(_ rawValue: String, relativeTo baseURL: URL) -> URL? {
        if rawValue.hasPrefix("http://") ||
            rawValue.hasPrefix("https://") ||
            rawValue.hasPrefix("file://") ||
            rawValue.hasPrefix("data:") ||
            rawValue.hasPrefix("mailto:") ||
            rawValue.hasPrefix("#") {
            return nil
        }

        let cleanedValue = rawValue.split(separator: "#", maxSplits: 1).first.map(String.init) ?? rawValue
        let querylessValue = cleanedValue.split(separator: "?", maxSplits: 1).first.map(String.init) ?? cleanedValue
        let candidate: URL

        if querylessValue.hasPrefix("/") {
            candidate = currentReadRoot.appendingPathComponent(String(querylessValue.dropFirst()))
        } else {
            candidate = baseURL.appendingPathComponent(querylessValue)
        }

        guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        return candidate
    }

    private func folderReaderHTML(_ html: String) -> String {
        let style = """

          <style id="htmelly-folder-reader-style">
            :root { color-scheme: light; }
            * { box-sizing: border-box; }
            html { background: #fff !important; }
            body {
              background: #fff !important;
              color: #1f2328 !important;
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif !important;
              font-size: 15px !important;
              line-height: 1.58 !important;
              margin: 0 auto !important;
              max-width: 980px !important;
              min-width: 0 !important;
              padding: 34px 34px 76px !important;
            }
            body > main,
            body > article,
            body > section,
            body > .content,
            body > .container,
            body > .wrapper {
              margin-left: auto !important;
              margin-right: auto !important;
              max-width: 920px !important;
              padding-left: 0 !important;
              padding-right: 0 !important;
            }
            header,
            .hero,
            .page-top,
            [class*="hero"],
            [class*="Hero"] {
              min-height: 0 !important;
              padding-bottom: 28px !important;
              padding-top: 28px !important;
            }
            body > :first-child { margin-top: 0 !important; }
            h1, h2, h3, h4 {
              color: #151820 !important;
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", sans-serif !important;
              letter-spacing: 0 !important;
            }
            h1 {
              font-size: clamp(28px, 4vw, 40px) !important;
              line-height: 1.12 !important;
              margin: 0 0 18px !important;
            }
            h2 {
              font-size: 23px !important;
              line-height: 1.18 !important;
              margin: 34px 0 12px !important;
            }
            h3 {
              font-size: 18px !important;
              line-height: 1.24 !important;
              margin: 26px 0 10px !important;
            }
            h4 {
              font-size: 15px !important;
              line-height: 1.32 !important;
              margin: 22px 0 8px !important;
            }
            p, li, dd, td, th {
              font-size: 15px !important;
              line-height: 1.58 !important;
            }
            p, ul, ol, blockquote, pre, table {
              margin-bottom: 16px !important;
            }
            ul, ol { padding-left: 24px !important; }
            a { color: #2f615c !important; text-decoration-thickness: 1px; text-underline-offset: 2px; }
            img, video, iframe, canvas, svg {
              height: auto !important;
              max-width: 100% !important;
            }
            pre {
              background: #111827 !important;
              border-radius: 8px !important;
              color: #e5e7eb !important;
              overflow: auto !important;
              padding: 14px 16px !important;
            }
            code {
              background: #f3f4f2 !important;
              border-radius: 5px !important;
              font-family: "SF Mono", ui-monospace, Menlo, monospace !important;
              font-size: 0.92em !important;
              padding: 2px 5px !important;
            }
            pre code {
              background: transparent !important;
              color: inherit !important;
              padding: 0 !important;
            }
            blockquote {
              border-left: 3px solid #d6d8d3 !important;
              color: #616975 !important;
              margin-left: 0 !important;
              padding-left: 14px !important;
            }
            table {
              border-collapse: collapse !important;
              display: block !important;
              max-width: 100% !important;
              overflow-x: auto !important;
              width: max-content !important;
            }
            th, td {
              border-bottom: 1px solid #e5e7eb !important;
              padding: 8px 10px !important;
              text-align: left !important;
              vertical-align: top !important;
            }
            th {
              color: #111827 !important;
              font-weight: 650 !important;
            }
            @media (max-width: 700px) {
              body {
                padding: 24px 18px 56px !important;
              }
              h1 { font-size: 30px !important; }
            }
          </style>
        """

        if let headEnd = html.range(of: "</head>", options: [.caseInsensitive]) {
            var output = html
            output.insert(contentsOf: style, at: headEnd.lowerBound)
            return output
        }

        return style + html
    }

    private func markdownPreviewHTML(_ markdown: String, title: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escapeHTML(title))</title>
          <style>
            body { background: #fff; color: #171923; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; margin: 0; }
            main { max-width: 780px; margin: 0 auto; padding: 36px 30px 72px; }
            h1 { font-size: 32px; line-height: 1.1; margin: 0 0 20px; }
            h2 { font-size: 23px; line-height: 1.18; margin: 34px 0 12px; }
            h3 { font-size: 18px; line-height: 1.24; margin: 26px 0 10px; }
            p, li { color: #374151; font-size: 15px; line-height: 1.58; }
            ul, ol { padding-left: 22px; }
            code { background: #f3f4f2; border-radius: 5px; padding: 2px 5px; }
            pre { background: #111827; border-radius: 8px; color: #e5e7eb; overflow: auto; padding: 16px; }
            pre code { background: transparent; padding: 0; }
            blockquote { border-left: 3px solid #d6d8d3; color: #6b7280; margin: 20px 0; padding-left: 14px; }
            hr { border: 0; border-top: 1px solid #e4e4df; margin: 28px 0; }
            a { color: #2f615c; }
            img, video, iframe { height: auto; max-width: 100%; }
            table { border-collapse: collapse; display: block; max-width: 100%; overflow-x: auto; width: max-content; }
            th, td { border-bottom: 1px solid #e5e7eb; padding: 8px 10px; text-align: left; vertical-align: top; }
            @media (max-width: 700px) { main { padding: 24px 18px 56px; } h1 { font-size: 29px; } }
          </style>
        </head>
        <body><main>\(renderMarkdown(markdown))</main></body>
        </html>
        """
    }

    private func renderMarkdown(_ markdown: String) -> String {
        var html: [String] = []
        var paragraph: [String] = []
        var inList = false
        var inCode = false
        var codeLines: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                html.append("<p>\(inlineMarkdown(paragraph.joined(separator: " ")))</p>")
                paragraph.removeAll()
            }
        }

        func closeList() {
            if inList {
                html.append("</ul>")
                inList = false
            }
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if inCode {
                    html.append("<pre><code>\(escapeHTML(codeLines.joined(separator: "\n")))</code></pre>")
                    codeLines.removeAll()
                    inCode = false
                } else {
                    flushParagraph()
                    closeList()
                    inCode = true
                }
                continue
            }

            if inCode {
                codeLines.append(rawLine)
                continue
            }

            if line.isEmpty {
                flushParagraph()
                closeList()
                continue
            }

            if line == "---" {
                flushParagraph()
                closeList()
                html.append("<hr>")
                continue
            }

            if line.hasPrefix("# ") || line.hasPrefix("## ") || line.hasPrefix("### ") {
                flushParagraph()
                closeList()
                let level = line.hasPrefix("### ") ? 3 : (line.hasPrefix("## ") ? 2 : 1)
                let markerCount = level + 1
                let text = String(line.dropFirst(markerCount)).trimmingCharacters(in: .whitespaces)
                html.append("<h\(level)>\(inlineMarkdown(text))</h\(level)>")
                continue
            }

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                if !inList {
                    html.append("<ul>")
                    inList = true
                }
                html.append("<li>\(inlineMarkdown(String(line.dropFirst(2))))</li>")
                continue
            }

            if line.hasPrefix("> ") {
                flushParagraph()
                closeList()
                html.append("<blockquote>\(inlineMarkdown(String(line.dropFirst(2))))</blockquote>")
                continue
            }

            paragraph.append(line)
        }

        flushParagraph()
        closeList()
        if inCode {
            html.append("<pre><code>\(escapeHTML(codeLines.joined(separator: "\n")))</code></pre>")
        }

        return html.joined(separator: "\n")
    }

    private func inlineMarkdown(_ text: String) -> String {
        var value = escapeHTML(text)
        value = value.replacingOccurrences(of: #"(`)([^`]+)(`)"#, with: "<code>$2</code>", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\[([^\]]+)\]\(([^)]+)\)"#, with: "<a href=\"$2\">$1</a>", options: .regularExpression)
        return value
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func loadMissingReportPage(_ report: Report) {
        let html = """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 42px; color: #1f2937; background: #f7f7f5; }
            main { max-width: 680px; background: white; border: 1px solid #e4e4df; border-radius: 10px; padding: 24px; }
            h1 { margin-top: 0; }
            p { color: #5f6673; line-height: 1.5; }
            code { background: #f0f1ee; padding: 2px 5px; border-radius: 5px; }
          </style>
        </head>
        <body>
          <main>
            <h1>Report file not found</h1>
            <p>The viewer expected this file:</p>
            <p><code>\(report.fileURL.path)</code></p>
            <p>Regenerate reports from this project, then reload. Current report folder:</p>
            <p><code>\(reportRoot.path)</code></p>
          </main>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: homeDirectory)
    }

    private func loadEmptyModePage() {
        let path = currentReadRoot?.path ?? ""
        let isFolderMode: Bool
        if case .folder = sourceMode {
            isFolderMode = true
        } else {
            isFolderMode = false
        }
        let summary = isFolderMode
            ? "This folder has no HTML or Markdown files HTTMELY can show."
            : "This built-in place has no pages available."
        let actionHTML = isFolderMode
            ? """
              <p class="actions">
                <a href="htmelly://add-folder">Add Folder...</a>
                <a href="htmelly://manage-places">Manage Places...</a>
              </p>
              """
            : "<p>Try switching places or adding a local folder.</p>"
        let html = """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 0; color: #1f2937; background: #fff; }
            main { max-width: 620px; padding: 36px 30px; }
            h1 { font-size: 22px; line-height: 1.15; margin: 0 0 10px; }
            p { color: #6b7280; line-height: 1.5; }
            code { background: #f0f1ee; padding: 2px 5px; border-radius: 5px; }
            .actions { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 18px; }
            .actions a {
              background: #f1f2ef;
              border-radius: 7px;
              color: #1f2937;
              display: inline-block;
              font-weight: 600;
              padding: 7px 10px;
              text-decoration: none;
            }
          </style>
        </head>
        <body>
          <main>
            <h1>No files found</h1>
            <p>\(summary)</p>
            <p><code>\(escapeHTML(path))</code></p>
            \(actionHTML)
          </main>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: currentReadRoot)
    }

    @objc private func reloadReport() {
        let selectedID = selectedReport?.id
        loadCurrentModeItems()
        rebuildSidebarItems()

        if let selectedID,
           let refreshedReport = currentItems.first(where: { $0.id == selectedID }) {
            selectReport(refreshedReport)
        } else if let firstReport = currentItems.first {
            selectReport(firstReport)
        } else {
            selectedReport = nil
            titleLabel.stringValue = currentModeTitle()
            if case .folder = sourceMode {
                subtitleLabel.stringValue = currentReadRoot.path
            } else {
                subtitleLabel.stringValue = "No files"
            }
            loadEmptyModePage()
        }
    }

    @objc private func toggleAppSidebar() {
        isAppSidebarVisible.toggle()
        defaults.set(isAppSidebarVisible, forKey: sidebarVisibleDefaultsKey)
        appSidebar.isHidden = !isAppSidebarVisible

        if isAppSidebarVisible {
            splitView.setPosition(230, ofDividerAt: 0)
        }

        splitView.adjustSubviews()
    }

    @objc private func toggleReportContentsSidebar() {
        isReportContentsVisible.toggle()
        defaults.set(isReportContentsVisible, forKey: contentsVisibleDefaultsKey)
        updateContentsButtonState()
        applyViewerMode()
    }

    private func updateContentsButtonState() {
        guard let contentsButton else { return }
        contentsButton.isEnabled = true
        contentsButton.state = isReportContentsVisible ? .on : .off
        contentsButton.contentTintColor = isReportContentsVisible ? .controlAccentColor : nil
        contentsButton.toolTip = isReportContentsVisible
            ? "Hide report contents (Command-Option-C)"
            : "Show report contents (Command-Option-C)"
    }

    @objc private func toggleTopBar() {
        isTopBarVisible.toggle()
        defaults.set(isTopBarVisible, forKey: topBarVisibleDefaultsKey)
        headerView.isHidden = !isTopBarVisible
        headerHeightConstraint.constant = isTopBarVisible ? 38 : 0
        topBarMenuItem?.state = isTopBarVisible ? .on : .off
        window.contentView?.layoutSubtreeIfNeeded()
    }

    @objc private func openInBrowser() {
        guard let selectedReport else { return }
        NSWorkspace.shared.open(selectedReport.fileURL)
    }

    @objc private func openReportFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let report = currentItems.first(where: { $0.id == id }) else {
            return
        }
        NSWorkspace.shared.open(report.fileURL)
    }

    @objc private func revealFile() {
        guard let selectedReport else { return }
        NSWorkspace.shared.activateFileViewerSelecting([selectedReport.fileURL])
    }

    @objc private func revealReportFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let report = currentItems.first(where: { $0.id == id }) else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([report.fileURL])
    }

    @objc private func revealCurrentFolder() {
        guard let currentReadRoot else { return }
        NSWorkspace.shared.activateFileViewerSelecting([currentReadRoot])
    }

    @objc private func exportCurrentFolder() {
        guard let sourceURL = currentReadRoot else { return }

        let panel = NSSavePanel()
        panel.title = "Export Full Folder"
        panel.message = "Choose where to copy the full \(currentModeTitle()) folder."
        panel.prompt = "Export"
        panel.nameFieldStringValue = "\(safeFileName(sourceURL.lastPathComponent))-export"
        panel.canCreateDirectories = true
        panel.directoryURL = sourceURL.deletingLastPathComponent()

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }
        copyFolder(from: sourceURL, to: destinationURL, successMessage: "Exported full folder to:\n\(destinationURL.path)")
    }

    @objc private func writeDatedArchiveCopy() {
        guard let sourceURL = currentReadRoot else { return }

        let archiveRoot = sourceURL
            .deletingLastPathComponent()
            .appendingPathComponent("_HTTMELY Archives", isDirectory: true)
        let folderName = "\(safeFileName(sourceURL.lastPathComponent))-\(dateStamp())"
        let destinationURL = archiveRoot.appendingPathComponent(folderName, isDirectory: true)

        copyFolder(from: sourceURL, to: destinationURL, successMessage: "Wrote dated archive copy to:\n\(destinationURL.path)")
    }

    private func copyFolder(from sourceURL: URL, to destinationURL: URL, successMessage: String) {
        do {
            let fileManager = FileManager.default
            let source = sourceURL.standardizedFileURL
            let destination = destinationURL.standardizedFileURL

            if destination.path.hasPrefix(source.path + "/") {
                showAlert(title: "Cannot copy inside itself", message: "Choose a destination outside the folder you are exporting.")
                return
            }

            if fileManager.fileExists(atPath: destination.path) {
                guard confirmReplace(destination) else { return }
                try fileManager.removeItem(at: destination)
            }

            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: destination)
            showAlert(title: "Done", message: successMessage)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            showAlert(title: "Export failed", message: error.localizedDescription)
        }
    }

    private func confirmReplace(_ destination: URL) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Replace existing folder?"
        alert.informativeText = destination.path
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "About \(appDisplayName)"
        alert.informativeText = "\(appDisplayName) is a local-first macOS reader for generated reports and folder-backed HTML or Markdown collections.\n\nReports stay on this Mac. Folder shortcuts are stored only in local user defaults."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func showHowToUse() {
        let alert = NSAlert()
        alert.messageText = "\(appDisplayName) Help"
        alert.informativeText = """
        Choose a place from the sidebar popup.
        Select a report in the sidebar.
        Use the bottom sidebar icons for previous, next, contents, and reload.
        Right-click a report to open it externally or reveal it in Finder.
        Use Places > Manage Places to rename, remove, or reorder folders.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func showKeyboardShortcuts() {
        let alert = NSAlert()
        alert.messageText = "Keyboard Shortcuts"
        alert.informativeText = """
        Command-[ / Command-] : previous or next report
        Command-R : reload
        Command-Option-C : contents
        Command-Option-S : sidebar
        Command-Option-F : add folder
        Command-Option-, : manage places
        Command-Option-1...9 : switch places
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }

    private func safeFileName(_ name: String) -> String {
        let cleaned = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "folder" : cleaned
    }

    private func applyViewerMode() {
        let showContents = isReportContentsVisible ? "true" : "false"
        let isReportsMode = sourceMode == .reports ? "true" : "false"
        let script = """
        (() => {
          const styleId = 'htmelly-native-viewer-style';
          const existingStyle = document.getElementById(styleId);
          const style = existingStyle || document.createElement('style');
          style.id = styleId;
          style.textContent = `
              body.htmelly-native-viewer {
                background: #fff !important;
                --htmelly-contents-width: 220px;
              }
              body.htmelly-native-viewer .shell {
                display: block !important;
                min-height: 100vh !important;
              }
              body.htmelly-native-viewer aside {
                display: none !important;
              }
              body.htmelly-native-viewer.htmelly-show-report-sidebar .shell {
                display: block !important;
              }
              body.htmelly-native-viewer.htmelly-show-report-sidebar aside {
                display: block !important;
                background: #f7f7f5 !important;
                border: 0 !important;
                border-right: 1px solid #e4e4df !important;
                bottom: 0 !important;
                box-sizing: border-box !important;
                height: 100vh !important;
                left: 0 !important;
                min-height: 0 !important;
                overflow: auto !important;
                padding: 18px 16px !important;
                position: fixed !important;
                top: 0 !important;
                width: var(--htmelly-contents-width) !important;
                z-index: 2 !important;
              }
              body.htmelly-native-viewer.htmelly-show-report-sidebar main {
                margin-left: var(--htmelly-contents-width) !important;
              }
              body.htmelly-native-viewer:not(.htmelly-show-report-sidebar) main {
                margin-left: 0 !important;
              }
              body.htmelly-native-viewer.htmelly-show-report-sidebar aside .toc-title {
                color: #9ca3af !important;
                font-size: 11px !important;
                font-weight: 760 !important;
                letter-spacing: 0.12em !important;
                margin: 0 0 10px !important;
              }
              body.htmelly-native-viewer.htmelly-show-report-sidebar aside a {
                color: #2f615c !important;
                display: block !important;
                font-size: 13px !important;
                line-height: 1.35 !important;
                margin: 0 0 9px !important;
              }
              body.htmelly-native-viewer.htmelly-show-report-sidebar aside .page-meta {
                color: #9ca3af !important;
                display: block !important;
                font-size: 11px !important;
                line-height: 1.35 !important;
                margin: 8px 0 0 !important;
              }
              body.htmelly-native-viewer main {
                padding: 14px 24px 42px !important;
              }
              body.htmelly-native-viewer .hero,
              body.htmelly-native-viewer .page-top {
                display: none !important;
              }
              body.htmelly-native-viewer .content {
                border: 0 !important;
                border-radius: 0 !important;
                box-shadow: none !important;
                padding: 0 !important;
                background: transparent !important;
              }
              body.htmelly-native-viewer section:first-child h2 {
                margin-top: 0 !important;
              }
              body.htmelly-native-viewer h2 {
                font-size: 20px !important;
                margin-top: 20px !important;
                margin-bottom: 10px !important;
              }
              body.htmelly-native-viewer p {
                line-height: 1.48 !important;
              }
              body.htmelly-native-viewer .page-meta {
                color: #9ca3af !important;
                font-size: 10px !important;
                line-height: 1.35 !important;
                margin-top: 16px !important;
              }
              body.htmelly-native-viewer .column-tools {
                display: none !important;
              }
              body.htmelly-native-viewer .table-wrap {
                border-radius: 6px !important;
                margin-bottom: 14px !important;
              }
              body.htmelly-native-viewer th,
              body.htmelly-native-viewer td {
                padding: 8px 10px !important;
              }
              body.htmelly-folder-viewer:not(.htmelly-show-report-sidebar) aside {
                display: none !important;
              }
              body.htmelly-folder-viewer:not(.htmelly-show-report-sidebar) .shell {
                display: block !important;
              }
              body.htmelly-folder-viewer:not(.htmelly-show-report-sidebar) main {
                margin-left: 0 !important;
                padding-left: 24px !important;
              }
              body.htmelly-folder-viewer.htmelly-show-report-sidebar .shell {
                display: block !important;
              }
              body.htmelly-folder-viewer.htmelly-show-report-sidebar aside {
                background: #f7f7f5 !important;
                border: 0 !important;
                border-right: 1px solid #e4e4df !important;
                bottom: 0 !important;
                box-sizing: border-box !important;
                display: block !important;
                height: 100vh !important;
                left: 0 !important;
                min-height: 0 !important;
                overflow: auto !important;
                padding: 18px 16px !important;
                position: fixed !important;
                top: 0 !important;
                width: 220px !important;
                z-index: 2 !important;
              }
              body.htmelly-folder-viewer.htmelly-show-report-sidebar main {
                margin-left: 220px !important;
              }
            `;
          if (!existingStyle) {
            document.head.appendChild(style);
          }
          const hasGeneratedContents = Boolean(document.querySelector('.shell > aside'));
          document.body.classList.toggle('htmelly-native-viewer', \(isReportsMode));
          document.body.classList.toggle('htmelly-folder-viewer', !\(isReportsMode));
          document.body.classList.toggle('htmelly-show-report-sidebar', \(showContents) && hasGeneratedContents);
        })();
        """
        webView.evaluateJavaScript(script)
    }
}

extension AppDelegate: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        guard tableView === placesManagerTableView else { return 0 }
        return folderModes.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard tableView === placesManagerTableView,
              row >= 0,
              row < folderModes.count,
              let tableColumn else {
            return nil
        }

        let mode = folderModes[row]
        let identifier = tableColumn.identifier
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier

        let textField: NSTextField
        if let existing = cell.textField {
            textField = existing
        } else {
            textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingMiddle
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        if identifier.rawValue == "order" {
            textField.stringValue = "\(row + 1)"
            textField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            textField.textColor = .tertiaryLabelColor
            textField.alignment = .right
            textField.lineBreakMode = .byTruncatingTail
        } else if identifier.rawValue == "name" {
            textField.stringValue = mode.title
            textField.font = .systemFont(ofSize: 13, weight: .medium)
            textField.textColor = .labelColor
            textField.alignment = .left
            textField.lineBreakMode = .byTruncatingTail
        } else {
            textField.stringValue = mode.folderURL.path
            textField.font = .systemFont(ofSize: 12, weight: .regular)
            textField.textColor = .secondaryLabelColor
            textField.alignment = .left
            textField.lineBreakMode = .byTruncatingMiddle
        }

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard notification.object as? NSTableView === placesManagerTableView else { return }
        updatePlacesManagerControls()
    }
}

extension AppDelegate: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyViewerMode()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else {
            return .allow
        }

        if url.scheme == "http" || url.scheme == "https" {
            NSWorkspace.shared.open(url)
            return .cancel
        }

        if url.scheme == "htmelly" {
            switch url.host {
            case "add-folder":
                addFolderMode()
            case "manage-places":
                showPlacesManager()
            default:
                break
            }
            return .cancel
        }

        if url.isFileURL {
            let pathExtension = url.pathExtension.lowercased()
            if pathExtension == "html" || pathExtension == "htm" || url.fragment != nil {
                return .allow
            }
            NSWorkspace.shared.open(url)
            return .cancel
        }

        return .allow
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
        }
        return nil
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
