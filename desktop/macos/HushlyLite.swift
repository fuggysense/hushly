import AppKit
import ApplicationServices
import AVFoundation
import AudioToolbox
import Carbon.HIToolbox

private let defaultAPIBase = "https://hushly-six.vercel.app"

@main
struct HushlyLiteApp {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, @unchecked Sendable {
  private var tabletPanel: NSPanel!
  private var tabletView: TabletView!
  private var statusLabel: NSTextField!
  private var statusItem: NSStatusItem!
  private var settingsWindow: NSWindow?
  private var tabletTextField: NSTextField?
  private var shortcutButton: NSButton?
  private var shortcutCaptureWindow: NSPanel?
  private var shortcutCaptureMonitor: Any?
  private var shortcutCaptureHintLabel: NSTextField?
  private var apiBaseField: NSTextField?
  private var mainStatusLabel: NSTextField?
  private var accessibilityStatusLabel: NSTextField?
  private var tabControl: NSSegmentedControl?
  private var settingsPane: NSView?
  private var historyPane: NSView?
  private var historyTable: NSTableView?
  private var historyDetailText: NSTextView?
  private var historyStorageLabel: NSTextField?
  private var historyActionStatusLabel: NSTextField?
  private var copyHistoryButton: NSButton?
  private var retryHistoryButton: NSButton?
  private var historyItems: [TranscriptEntry] = []
  private var hotKeyRef: EventHotKeyRef?
  private var escapeHotKeyRef: EventHotKeyRef?
  private var eventHandlerRef: EventHandlerRef?
  private var escapeLocalMonitor: Any?
  private var escapeGlobalMonitor: Any?
  private var recorder: AVAudioRecorder?
  private var recordingURL: URL?
  private var pasteTargetApp: NSRunningApplication?
  private var lastExternalApp: NSRunningApplication?
  private var animationTimer: Timer?
  private var smoothedAudioLevel: CGFloat = 0
  private var isRecording = false
  private lazy var popSound: NSSound? = {
    let sound =
      NSSound(contentsOfFile: "/System/Library/Sounds/Pop.aiff", byReference: true)
      ?? NSSound(named: NSSound.Name("Pop"))
    sound?.volume = 0.75
    return sound
  }()

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    buildMainMenu()
    buildStatusItem()
    buildTabletPanel()
    historyItems = TranscriptStore.shared.load()
    observeActiveApps()
    installHotKeyHandler()
    registerHotKey()
    showSettings()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
      self.refreshSettingsFields()
      self.setReadyStatus()
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    showSettings()
    return true
  }

  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    false
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    refreshAccessibilityStatus()
    if !isRecording {
      setReadyStatus()
    }
  }

  func windowWillClose(_ notification: Notification) {
    if notification.object as? NSWindow === settingsWindow {
      settingsWindow = nil
      tabletTextField = nil
      shortcutButton = nil
      apiBaseField = nil
      mainStatusLabel = nil
      accessibilityStatusLabel = nil
      tabControl = nil
      settingsPane = nil
      historyPane = nil
      historyTable = nil
      historyDetailText = nil
      historyStorageLabel = nil
      historyActionStatusLabel = nil
      copyHistoryButton = nil
      retryHistoryButton = nil
    } else if notification.object as? NSWindow === shortcutCaptureWindow {
      removeShortcutCaptureMonitor()
      shortcutCaptureWindow = nil
      shortcutCaptureHintLabel = nil
      registerHotKey()
      refreshSettingsFields()
      setReadyStatus()
    }
  }

  private func buildStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.title = "hushly"

    let menu = NSMenu()
    menu.addItem(menuItem("Open Hushly", action: #selector(showSettings), key: ""))
    menu.addItem(menuItem("Start / Stop Dictation", action: #selector(toggleDictation), key: "d"))
    menu.addItem(menuItem("Open Accessibility Settings", action: #selector(openAccessibilitySettings), key: ""))
    menu.addItem(.separator())
    menu.addItem(menuItem("Quit Hushly", action: #selector(NSApplication.terminate(_:)), key: "q"))
    statusItem.menu = menu
  }

  private func buildMainMenu() {
    let mainMenu = NSMenu()

    let appMenuItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(menuItem("Open Settings", action: #selector(showSettings), key: ","))
    appMenu.addItem(.separator())
    appMenu.addItem(NSMenuItem(title: "Hide Hushly", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
    appMenu.addItem(NSMenuItem(title: "Quit Hushly", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    appMenuItem.submenu = appMenu
    mainMenu.addItem(appMenuItem)

    let windowMenuItem = NSMenuItem()
    let windowMenu = NSMenu(title: "Window")
    windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
    windowMenu.addItem(menuItem("Open Settings", action: #selector(showSettings), key: ""))
    windowMenuItem.submenu = windowMenu
    mainMenu.addItem(windowMenuItem)
    NSApp.windowsMenu = windowMenu

    NSApp.mainMenu = mainMenu
  }

  private func menuItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.target = self
    return item
  }

  private func observeActiveApps() {
    if let app = currentExternalApp() {
      lastExternalApp = app
    }

    NSWorkspace.shared.notificationCenter.addObserver(
      self,
      selector: #selector(activeAppChanged(_:)),
      name: NSWorkspace.didActivateApplicationNotification,
      object: nil
    )
  }

  @objc private func activeAppChanged(_ notification: Notification) {
    guard
      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
      app.bundleIdentifier != Bundle.main.bundleIdentifier
    else {
      return
    }
    lastExternalApp = app
  }

  private func currentExternalApp() -> NSRunningApplication? {
    let app = NSWorkspace.shared.frontmostApplication
    return app?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : app
  }

  private func buildTabletPanel() {
    let contentRect = NSRect(x: 0, y: 0, width: 216, height: 50)
    tabletPanel = NSPanel(
      contentRect: contentRect,
      styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    tabletPanel.title = "Hushly"
    tabletPanel.titleVisibility = .hidden
    tabletPanel.titlebarAppearsTransparent = true
    tabletPanel.isMovableByWindowBackground = true
    tabletPanel.isReleasedWhenClosed = false
    tabletPanel.hidesOnDeactivate = false
    tabletPanel.backgroundColor = NSColor(calibratedWhite: 0.02, alpha: 0.94)
    tabletPanel.isOpaque = false
    tabletPanel.hasShadow = true
    tabletPanel.level = .floating
    tabletPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    tabletPanel.delegate = self
    tabletPanel.standardWindowButton(.closeButton)?.isHidden = true
    tabletPanel.standardWindowButton(.miniaturizeButton)?.isHidden = true
    tabletPanel.standardWindowButton(.zoomButton)?.isHidden = true

    let content = NSView(frame: contentRect)
    content.wantsLayer = true
    content.layer?.backgroundColor = NSColor(calibratedWhite: 0.02, alpha: 0.94).cgColor
    content.layer?.cornerRadius = 13
    content.layer?.masksToBounds = true

    tabletView = TabletView(frame: NSRect(x: 8, y: 14, width: 200, height: 31))
    tabletView.displayText = Preferences.shared.tabletText
    content.addSubview(tabletView)

    statusLabel = NSTextField(labelWithString: "Ready")
    statusLabel.frame = NSRect(x: 12, y: 3, width: 192, height: 10)
    statusLabel.textColor = NSColor.white.withAlphaComponent(0.72)
    statusLabel.font = NSFont.systemFont(ofSize: 8, weight: .medium)
    statusLabel.lineBreakMode = .byTruncatingTail
    statusLabel.maximumNumberOfLines = 1
    content.addSubview(statusLabel)

    tabletPanel.contentView = content
  }

  @objc private func showTabletFromMenu() {
    showTabletPanel(positionAtBottom: false)
  }

  private func showTabletPanel(positionAtBottom: Bool) {
    if positionAtBottom || !tabletPanel.isVisible {
      placeTabletAtBottom()
    }
    tabletPanel.orderFrontRegardless()
  }

  private func placeTabletAtBottom() {
    guard let screen = NSScreen.main else { return }
    let visible = screen.visibleFrame
    let size = tabletPanel.frame.size
    let origin = NSPoint(
      x: visible.midX - (size.width / 2),
      y: visible.minY + 18
    )
    tabletPanel.setFrameOrigin(origin)
  }

  @objc private func toggleDictation() {
    if isRecording {
      stopRecording()
    } else {
      startRecording()
    }
  }

  private func startRecording() {
    guard !isRecording else { return }

    pasteTargetApp = currentExternalApp() ?? lastExternalApp
    showTabletPanel(positionAtBottom: true)
    refreshAccessibilityStatus()
    requestMicrophoneAccess { [weak self] granted in
      guard let self else { return }
      DispatchQueue.main.async {
        guard granted else {
          self.setStatus("Microphone permission is needed.")
          self.hideTablet(after: 1.4)
          return
        }
        self.beginRecorder()
      }
    }
  }

  private func beginRecorder() {
    do {
      let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("hushly-\(UUID().uuidString)")
        .appendingPathExtension("m4a")
      let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]
      let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
      recorder.isMeteringEnabled = true
      recorder.prepareToRecord()
      recorder.record()

      self.recorder = recorder
      self.recordingURL = fileURL
      self.isRecording = true
      self.smoothedAudioLevel = 0
      self.tabletView.isRecording = true
      self.tabletView.audioLevel = 0
      self.tabletView.displayText = Preferences.shared.tabletText
      registerEscapeHotKey()
      installEscapeMonitors()
      startGlowAnimation()
      playStartSound()
      setStatus("Listening")
    } catch {
      setStatus("Recorder failed: \(error.localizedDescription)")
    }
  }

  private func stopRecording() {
    guard isRecording else { return }
    let fileURL = recordingURL
    recorder?.stop()
    recorder = nil
    recordingURL = nil
    isRecording = false
    tabletView.isRecording = false
    tabletView.audioLevel = 0
    unregisterEscapeHotKey()
    removeEscapeMonitors()
    stopGlowAnimation()
    playStopSound()
    setStatus("Transcribing")

    guard let fileURL else {
      setStatus("No recording found.")
      return
    }

    Task { [weak self] in
      await self?.processRecording(fileURL)
    }
  }

  private func cancelRecordingForRetry() {
    guard isRecording else { return }
    let fileURL = recordingURL
    recorder?.stop()
    recorder = nil
    recordingURL = nil
    isRecording = false
    tabletView.isRecording = false
    tabletView.audioLevel = 0
    unregisterEscapeHotKey()
    removeEscapeMonitors()
    stopGlowAnimation()
    playStopSound()

    guard let fileURL else {
      setStatus("No recording found.")
      hideTablet(after: 1.2)
      return
    }

    do {
      let savedURL = try TranscriptStore.shared.storeAudio(fileURL)
      let entry = TranscriptEntry(
        id: UUID().uuidString,
        createdAt: Date(),
        rawText: "",
        cleanedText: "",
        audioPath: savedURL.path,
        status: "Saved for retry"
      )
      insertHistoryEntry(entry)
      setStatus("Saved for retry")
    } catch {
      setStatus("Cancel save failed")
    }

    try? FileManager.default.removeItem(at: fileURL)
    hideTablet(after: 1.2)
  }

  private func processRecording(_ fileURL: URL) async {
    defer { try? FileManager.default.removeItem(at: fileURL) }

    do {
      let transcript = try await transcribe(fileURL: fileURL)
      guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        setStatus("No speech detected.")
        hideTablet(after: 1.2)
        return
      }

      setStatus("Cleaning")
      let finalText: String
      do {
        finalText = try await clean(transcript: transcript)
      } catch {
        finalText = transcript
        setStatus("Cleanup unavailable; pasting raw.")
      }

      let savedURL = try? TranscriptStore.shared.storeAudio(fileURL)
      insertHistoryEntry(
        TranscriptEntry(
          id: UUID().uuidString,
          createdAt: Date(),
          rawText: transcript,
          cleanedText: finalText,
          audioPath: savedURL?.path,
          status: "Complete"
        )
      )
      paste(finalText)
    } catch {
      setStatus(error.localizedDescription)
      hideTablet(after: 2.0)
    }
  }

  private func insertHistoryEntry(_ entry: TranscriptEntry) {
    DispatchQueue.main.async {
      self.historyItems.insert(entry, at: 0)
      TranscriptStore.shared.save(self.historyItems)
      self.refreshHistoryUI()
    }
  }

  private func transcribe(fileURL: URL) async throws -> String {
    var request = URLRequest(url: apiURL(path: "/transcribe"))
    request.httpMethod = "POST"
    request.setValue("audio/m4a", forHTTPHeaderField: "Content-Type")

    let data = try Data(contentsOf: fileURL)
    let (responseData, response) = try await URLSession.shared.upload(for: request, from: data)
    let json = try decodeAPIResponse(data: responseData, response: response, label: "transcribe")
    return json["transcript"] as? String ?? ""
  }

  private func clean(transcript: String) async throws -> String {
    var request = URLRequest(url: apiURL(path: "/clean"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let payload = try JSONSerialization.data(withJSONObject: ["text": transcript])
    let (responseData, response) = try await URLSession.shared.upload(for: request, from: payload)
    let json = try decodeAPIResponse(data: responseData, response: response, label: "clean")
    return json["cleaned"] as? String ?? transcript
  }

  private func decodeAPIResponse(data: Data, response: URLResponse, label: String) throws -> [String: Any] {
    guard let http = response as? HTTPURLResponse else {
      throw HushlyError.api("\(label): invalid server response")
    }

    guard (200..<300).contains(http.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw HushlyError.api("\(label) \(http.statusCode): \(body.prefix(220))")
    }

    let object = try JSONSerialization.jsonObject(with: data)
    return object as? [String: Any] ?? [:]
  }

  private func apiURL(path: String) -> URL {
    let base = Preferences.shared.apiBase
    return URL(string: "\(base)\(path)")!
  }

  private func paste(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)

    guard ensureAccessibilityPermission(prompt: true) else {
      refreshAccessibilityStatus()
      setStatus("Clipboard ready. Enable auto-paste.")
      hideTablet(after: 2.0)
      return
    }

    refreshAccessibilityStatus()
    guard let target = pasteTargetApp, target.bundleIdentifier != Bundle.main.bundleIdentifier else {
      setStatus("Clipboard ready. Focus target first.")
      hideTablet(after: 2.0)
      return
    }

    target.activate(options: [.activateAllWindows])
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
      let source = CGEventSource(stateID: .combinedSessionState)
      let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
      keyDown?.flags = .maskCommand
      keyUp?.flags = .maskCommand
      keyDown?.post(tap: .cghidEventTap)
      keyUp?.post(tap: .cghidEventTap)
      self.setStatus("Pasted")
      self.hideTablet(after: 0.9)
    }
  }

  private func requestMicrophoneAccess(_ completion: @escaping (Bool) -> Void) {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      completion(true)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    case .denied, .restricted:
      completion(false)
    @unknown default:
      completion(false)
    }
  }

  private func ensureAccessibilityPermission(prompt: Bool) -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  @objc private func openAccessibilitySettings() {
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    NSWorkspace.shared.open(url)
  }

  @objc private func showSettings() {
    if settingsWindow == nil {
      buildSettingsWindow()
    }

    guard let window = settingsWindow else { return }
    tabletTextField?.stringValue = Preferences.shared.tabletText
    apiBaseField?.stringValue = Preferences.shared.apiBase
    refreshSettingsFields()
    if !isRecording {
      setReadyStatus()
    }
    NSApp.activate(ignoringOtherApps: true)
    if !window.isVisible {
      window.center()
    }
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
    window.makeKeyAndOrderFront(nil)
    DispatchQueue.main.async {
      self.refreshSettingsFields()
      if !self.isRecording {
        self.setReadyStatus()
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      self.refreshSettingsFields()
      if !self.isRecording {
        self.setReadyStatus()
      }
    }
  }

  private func buildSettingsWindow() {
    let width: CGFloat = 620
    let height: CGFloat = 520
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: width, height: height),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Hushly"
    window.isReleasedWhenClosed = false
    window.isRestorable = false
    window.delegate = self

    let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

    let tabs = NSSegmentedControl(labels: ["Settings", "History"], trackingMode: .selectOne, target: self, action: #selector(switchMainPane))
    tabs.frame = NSRect(x: 24, y: height - 48, width: 220, height: 28)
    tabs.selectedSegment = 0
    content.addSubview(tabs)
    tabControl = tabs

    let paneFrame = NSRect(x: 0, y: 0, width: width, height: height - 64)
    let settingsPane = buildSettingsPane(frame: paneFrame)
    let historyPane = buildHistoryPane(frame: paneFrame)
    historyPane.isHidden = true

    content.addSubview(settingsPane)
    content.addSubview(historyPane)
    self.settingsPane = settingsPane
    self.historyPane = historyPane

    window.contentView = content
    settingsWindow = window
    refreshSettingsFields()
    refreshHistoryUI()
  }

  private func buildSettingsPane(frame: NSRect) -> NSView {
    let content = NSView(frame: frame)
    let textLabel = NSTextField(labelWithString: "Tablet text")
    textLabel.frame = NSRect(x: 32, y: 376, width: 120, height: 18)
    content.addSubview(textLabel)

    let textField = NSTextField(string: Preferences.shared.tabletText)
    textField.frame = NSRect(x: 168, y: 370, width: 396, height: 30)
    content.addSubview(textField)
    tabletTextField = textField

    let shortcutLabel = NSTextField(labelWithString: "Shortcut")
    shortcutLabel.frame = NSRect(x: 32, y: 318, width: 120, height: 18)
    content.addSubview(shortcutLabel)

    let shortcutButton = NSButton(title: Preferences.shared.shortcut.title, target: self, action: #selector(beginShortcutCapture))
    shortcutButton.frame = NSRect(x: 168, y: 312, width: 396, height: 32)
    shortcutButton.bezelStyle = .rounded
    content.addSubview(shortcutButton)
    self.shortcutButton = shortcutButton

    let apiLabel = NSTextField(labelWithString: "API base")
    apiLabel.frame = NSRect(x: 32, y: 260, width: 120, height: 18)
    content.addSubview(apiLabel)

    let apiField = NSTextField(string: Preferences.shared.apiBase)
    apiField.frame = NSRect(x: 168, y: 254, width: 396, height: 30)
    content.addSubview(apiField)
    apiBaseField = apiField

    let accessStatus = NSTextField(labelWithString: accessibilityStatusText())
    accessStatus.frame = NSRect(x: 32, y: 206, width: 532, height: 18)
    accessStatus.textColor = NSColor.secondaryLabelColor
    accessStatus.font = NSFont.systemFont(ofSize: 11)
    accessStatus.lineBreakMode = .byTruncatingTail
    accessStatus.maximumNumberOfLines = 1
    content.addSubview(accessStatus)
    accessibilityStatusLabel = accessStatus

    let mainStatus = NSTextField(labelWithString: "Ready: \(Preferences.shared.shortcut.title)")
    mainStatus.frame = NSRect(x: 32, y: 174, width: 532, height: 18)
    mainStatus.textColor = NSColor.secondaryLabelColor
    mainStatus.font = NSFont.systemFont(ofSize: 12, weight: .medium)
    mainStatus.lineBreakMode = .byTruncatingTail
    mainStatus.maximumNumberOfLines = 1
    content.addSubview(mainStatus)
    mainStatusLabel = mainStatus

    let dictateButton = NSButton(title: "Dictate", target: self, action: #selector(toggleDictation))
    dictateButton.frame = NSRect(x: 360, y: 112, width: 96, height: 32)
    dictateButton.bezelStyle = .rounded
    content.addSubview(dictateButton)

    let saveButton = NSButton(title: "Save", target: self, action: #selector(saveSettings))
    saveButton.frame = NSRect(x: 468, y: 112, width: 96, height: 32)
    saveButton.bezelStyle = .rounded
    content.addSubview(saveButton)

    return content
  }

  private func buildHistoryPane(frame: NSRect) -> NSView {
    let content = NSView(frame: frame)

    let storageLabel = NSTextField(labelWithString: historyStorageText())
    storageLabel.frame = NSRect(x: 24, y: 404, width: 572, height: 18)
    storageLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
    storageLabel.textColor = NSColor.secondaryLabelColor
    storageLabel.lineBreakMode = .byTruncatingMiddle
    content.addSubview(storageLabel)
    historyStorageLabel = storageLabel

    let scrollView = NSScrollView(frame: NSRect(x: 24, y: 164, width: 572, height: 224))
    scrollView.borderType = .bezelBorder
    scrollView.hasVerticalScroller = true

    let table = NSTableView(frame: scrollView.bounds)
    table.headerView = nil
    table.rowHeight = 34
    table.intercellSpacing = NSSize(width: 8, height: 4)
    table.delegate = self
    table.dataSource = self
    table.usesAlternatingRowBackgroundColors = false
    table.allowsMultipleSelection = false
    addHistoryColumn(to: table, id: "date", title: "Date", width: 126)
    addHistoryColumn(to: table, id: "status", title: "Status", width: 104)
    addHistoryColumn(to: table, id: "text", title: "Transcript", width: 326)
    scrollView.documentView = table
    content.addSubview(scrollView)
    historyTable = table

    let detailScroll = NSScrollView(frame: NSRect(x: 24, y: 70, width: 572, height: 78))
    detailScroll.borderType = .bezelBorder
    detailScroll.hasVerticalScroller = true
    let detail = NSTextView(frame: detailScroll.bounds)
    detail.isEditable = false
    detail.isSelectable = true
    detail.drawsBackground = false
    detail.font = NSFont.systemFont(ofSize: 12)
    detail.textColor = NSColor.labelColor
    detail.textContainerInset = NSSize(width: 8, height: 8)
    detailScroll.documentView = detail
    content.addSubview(detailScroll)
    historyDetailText = detail

    let actionStatus = NSTextField(labelWithString: "")
    actionStatus.frame = NSRect(x: 24, y: 30, width: 308, height: 18)
    actionStatus.font = NSFont.systemFont(ofSize: 11)
    actionStatus.textColor = NSColor.secondaryLabelColor
    actionStatus.lineBreakMode = .byTruncatingTail
    content.addSubview(actionStatus)
    historyActionStatusLabel = actionStatus

    let copyButton = NSButton(title: "Copy", target: self, action: #selector(copySelectedHistory))
    copyButton.frame = NSRect(x: 372, y: 24, width: 92, height: 30)
    copyButton.bezelStyle = .rounded
    content.addSubview(copyButton)
    copyHistoryButton = copyButton

    let retryButton = NSButton(title: "Retry", target: self, action: #selector(retrySelectedHistory))
    retryButton.frame = NSRect(x: 480, y: 24, width: 92, height: 30)
    retryButton.bezelStyle = .rounded
    content.addSubview(retryButton)
    retryHistoryButton = retryButton

    return content
  }

  private func addHistoryColumn(to table: NSTableView, id: String, title: String, width: CGFloat) {
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
    column.title = title
    column.width = width
    column.minWidth = width
    table.addTableColumn(column)
  }

  @objc private func switchMainPane() {
    let showingHistory = tabControl?.selectedSegment == 1
    settingsPane?.isHidden = showingHistory
    historyPane?.isHidden = !showingHistory
    if showingHistory {
      refreshHistoryUI()
    }
  }

  private func refreshSettingsFields() {
    tabletTextField?.stringValue = Preferences.shared.tabletText
    apiBaseField?.stringValue = Preferences.shared.apiBase
    shortcutButton?.title = Preferences.shared.shortcut.title
    refreshAccessibilityStatus()
  }

  private func refreshHistoryUI() {
    historyStorageLabel?.stringValue = historyStorageText()
    let selectedRow = historyTable?.selectedRow ?? -1
    historyTable?.reloadData()

    if historyItems.isEmpty {
      historyTable?.deselectAll(nil)
    } else if selectedRow >= 0 && selectedRow < historyItems.count {
      historyTable?.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
    } else if historyTable?.selectedRow == -1 {
      historyTable?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }

    refreshHistoryDetail()
  }

  private func refreshHistoryDetail() {
    guard let index = selectedHistoryIndex() else {
      historyDetailText?.string = "No transcripts saved on this Mac yet."
      copyHistoryButton?.isEnabled = false
      retryHistoryButton?.isEnabled = false
      return
    }

    let entry = historyItems[index]
    historyDetailText?.string = displayText(for: entry)
    copyHistoryButton?.isEnabled = transcriptText(for: entry) != nil
    retryHistoryButton?.isEnabled = entry.audioPath != nil
  }

  private func selectedHistoryIndex() -> Int? {
    guard let row = historyTable?.selectedRow, row >= 0, row < historyItems.count else {
      return nil
    }
    return row
  }

  private func displayText(for entry: TranscriptEntry) -> String {
    transcriptText(for: entry) ?? (entry.audioPath == nil ? "" : "(audio saved for retry)")
  }

  private func transcriptText(for entry: TranscriptEntry) -> String? {
    let cleaned = entry.cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !cleaned.isEmpty { return cleaned }
    let raw = entry.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    return raw.isEmpty ? nil : raw
  }

  private func historyStorageText() -> String {
    "Storage: local on this Mac. Supabase sync: not connected in the desktop app."
  }

  private func formatHistoryDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }

  @objc private func copySelectedHistory() {
    guard let index = selectedHistoryIndex() else { return }
    guard let text = transcriptText(for: historyItems[index]) else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    historyActionStatusLabel?.stringValue = "Copied"
  }

  @objc private func retrySelectedHistory() {
    guard let index = selectedHistoryIndex() else { return }
    let entry = historyItems[index]
    guard let audioPath = entry.audioPath else {
      historyActionStatusLabel?.stringValue = "No audio saved for retry"
      return
    }

    let fileURL = URL(fileURLWithPath: audioPath)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      historyActionStatusLabel?.stringValue = "Audio file is missing"
      return
    }

    retryHistoryButton?.isEnabled = false
    historyActionStatusLabel?.stringValue = "Retrying..."
    Task { [weak self] in
      await self?.retryHistoryEntry(id: entry.id, fileURL: fileURL)
    }
  }

  private func retryHistoryEntry(id: String, fileURL: URL) async {
    do {
      let transcript = try await transcribe(fileURL: fileURL)
      guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw HushlyError.api("No speech detected.")
      }

      let finalText: String
      do {
        finalText = try await clean(transcript: transcript)
      } catch {
        finalText = transcript
      }

      DispatchQueue.main.async { [weak self] in
        guard let self, let index = self.historyItems.firstIndex(where: { $0.id == id }) else { return }
        self.historyItems[index].rawText = transcript
        self.historyItems[index].cleanedText = finalText
        self.historyItems[index].status = "Complete"
        TranscriptStore.shared.save(self.historyItems)
        self.refreshHistoryUI()
        if let row = self.historyItems.firstIndex(where: { $0.id == id }) {
          self.historyTable?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        self.historyActionStatusLabel?.stringValue = "Retry complete"
      }
    } catch {
      let message = error.localizedDescription
      DispatchQueue.main.async { [weak self] in
        self?.retryHistoryButton?.isEnabled = true
        self?.historyActionStatusLabel?.stringValue = message
      }
    }
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    historyItems.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard row >= 0, row < historyItems.count else { return nil }
    let columnID = tableColumn?.identifier.rawValue ?? "text"
    let cellID = NSUserInterfaceItemIdentifier("history-\(columnID)")
    let label = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTextField ?? NSTextField(labelWithString: "")
    label.identifier = cellID
    label.frame = NSRect(x: 4, y: 0, width: max(40, (tableColumn?.width ?? 200) - 8), height: tableView.rowHeight)
    label.autoresizingMask = [.width, .height]
    label.lineBreakMode = .byTruncatingTail
    label.maximumNumberOfLines = 1

    let entry = historyItems[row]
    switch columnID {
    case "date":
      label.stringValue = formatHistoryDate(entry.createdAt)
    case "status":
      label.stringValue = entry.status
    default:
      label.stringValue = displayText(for: entry)
    }
    label.textColor = columnID == "status" ? NSColor.secondaryLabelColor : NSColor.labelColor
    label.font = NSFont.systemFont(ofSize: 12)
    return label
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    refreshHistoryDetail()
  }

  @objc private func beginShortcutCapture() {
    showShortcutCaptureWindow()
    setStatus("Press your shortcut")
  }

  private func showShortcutCaptureWindow() {
    removeShortcutCaptureMonitor()
    if let shortcutCaptureWindow {
      shortcutCaptureWindow.delegate = nil
      shortcutCaptureWindow.close()
      self.shortcutCaptureWindow = nil
      shortcutCaptureHintLabel = nil
    }
    unregisterHotKey()

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 340, height: 132),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    panel.title = "Set Shortcut"
    panel.isReleasedWhenClosed = false
    panel.isRestorable = false
    panel.delegate = self

    let content = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 132))
    let title = NSTextField(labelWithString: "Press the shortcut you want")
    title.frame = NSRect(x: 28, y: 78, width: 284, height: 22)
    title.alignment = .center
    title.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
    content.addSubview(title)

    let hint = NSTextField(labelWithString: "Use a modifier with a key, or press F1-F20. Esc cancels.")
    hint.frame = NSRect(x: 28, y: 50, width: 284, height: 18)
    hint.alignment = .center
    hint.textColor = .secondaryLabelColor
    hint.font = NSFont.systemFont(ofSize: 11)
    content.addSubview(hint)
    shortcutCaptureHintLabel = hint

    let captureView = ShortcutCaptureView(frame: content.bounds)
    captureView.onShortcut = { [weak self] shortcut in
      guard let self else { return }
      self.acceptShortcutCapture(shortcut)
    }
    captureView.onCancel = { [weak self] in
      guard let self else { return }
      self.cancelShortcutCapture()
    }
    content.addSubview(captureView, positioned: .below, relativeTo: title)

    panel.contentView = content
    shortcutCaptureWindow = panel
    NSApp.activate(ignoringOtherApps: true)
    panel.center()
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(captureView)
    installShortcutCaptureMonitor()
  }

  private func captureShortcut(_ shortcut: ShortcutOption) {
    Preferences.shared.shortcut = shortcut
    registerHotKey()
    refreshSettingsFields()
  }

  private func installShortcutCaptureMonitor() {
    shortcutCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
      guard let self, self.shortcutCaptureWindow?.isVisible == true else {
        return event
      }

      self.handleShortcutCaptureEvent(event)
      return nil
    }
  }

  private func removeShortcutCaptureMonitor() {
    if let shortcutCaptureMonitor {
      NSEvent.removeMonitor(shortcutCaptureMonitor)
      self.shortcutCaptureMonitor = nil
    }
  }

  private func handleShortcutCaptureEvent(_ event: NSEvent) {
    if event.type == .flagsChanged {
      updateShortcutCaptureHint(with: event)
      return
    }

    if event.keyCode == UInt16(kVK_Escape) {
      cancelShortcutCapture()
      return
    }

    guard let shortcut = shortcutCandidate(from: event) else {
      shortcutCaptureHintLabel?.stringValue = "Use a modifier with a key, or press F1-F20."
      NSSound.beep()
      return
    }

    guard canRegisterShortcut(shortcut) else {
      shortcutCaptureHintLabel?.stringValue = "\(shortcut.title) is already used by macOS. Try another."
      NSSound.beep()
      return
    }

    acceptShortcutCapture(shortcut)
  }

  private func updateShortcutCaptureHint(with event: NSEvent) {
    let modifiers = carbonModifiers(from: event.modifierFlags)
    guard modifiers != 0 else {
      shortcutCaptureHintLabel?.stringValue = "Use a modifier with a key, or press F1-F20."
      return
    }

    shortcutCaptureHintLabel?.stringValue = "\(modifierTitle(modifiers)) + key"
  }

  private func acceptShortcutCapture(_ shortcut: ShortcutOption) {
    removeShortcutCaptureMonitor()
    shortcutCaptureWindow?.delegate = nil
    shortcutCaptureWindow?.close()
    shortcutCaptureWindow = nil
    shortcutCaptureHintLabel = nil
    captureShortcut(shortcut)
    setStatus("Shortcut set: \(shortcut.title)")
  }

  private func cancelShortcutCapture() {
    removeShortcutCaptureMonitor()
    shortcutCaptureWindow?.delegate = nil
    shortcutCaptureWindow?.close()
    shortcutCaptureWindow = nil
    shortcutCaptureHintLabel = nil
    registerHotKey()
    refreshSettingsFields()
    setReadyStatus()
  }

  private func shortcutCandidate(from event: NSEvent) -> ShortcutOption? {
    let keyCode = UInt32(event.keyCode)
    let modifiers = carbonModifiers(from: event.modifierFlags)
    let hasModifier = modifiers != 0
    guard hasModifier || isStandaloneShortcutKey(keyCode) else { return nil }

    let title = shortcutTitle(
      keyCode: keyCode,
      modifiers: modifiers,
      fallbackLabel: event.charactersIgnoringModifiers?.uppercased()
    )
    return ShortcutOption(
      id: "custom-\(keyCode)-\(modifiers)",
      title: title,
      keyCode: keyCode,
      modifiers: modifiers
    )
  }

  private func canRegisterShortcut(_ shortcut: ShortcutOption) -> Bool {
    var temporaryRef: EventHotKeyRef?
    let hotKeyID = EventHotKeyID(signature: fourCharCode("hush"), id: 99)
    let status = RegisterEventHotKey(
      shortcut.keyCode,
      shortcut.modifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &temporaryRef
    )
    if let temporaryRef {
      UnregisterEventHotKey(temporaryRef)
    }
    return status == noErr
  }

  @objc private func saveSettings() {
    if let text = tabletTextField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
      Preferences.shared.tabletText = text
      tabletView.displayText = text
    }

    if let apiBase = apiBaseField?.stringValue {
      Preferences.shared.apiBase = apiBase
    }

    setStatus("Settings saved")
    refreshSettingsFields()
  }

  private func installHotKeyHandler() {
    guard eventHandlerRef == nil else { return }

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let userData else { return noErr }
        let app = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
        let id = app.hotKeyID(from: event)
        DispatchQueue.main.async {
          switch id {
          case 2:
            app.cancelRecordingForRetry()
          default:
            app.toggleDictation()
          }
        }
        return noErr
      },
      1,
      &eventType,
      UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
      &eventHandlerRef
    )
  }

  private func registerHotKey() {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
      self.hotKeyRef = nil
    }

    let shortcut = Preferences.shared.shortcut
    let hotKeyID = EventHotKeyID(signature: fourCharCode("hush"), id: 1)
    let status = RegisterEventHotKey(
      shortcut.keyCode,
      shortcut.modifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )

    if status == noErr {
      setStatus("Ready: \(shortcut.title)")
    } else {
      setStatus("Shortcut unavailable. Change it in Settings.")
    }
  }

  private func unregisterHotKey() {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
      self.hotKeyRef = nil
    }
  }

  private func registerEscapeHotKey() {
    if escapeHotKeyRef != nil { return }
    let hotKeyID = EventHotKeyID(signature: fourCharCode("hush"), id: 2)
    RegisterEventHotKey(
      UInt32(kVK_Escape),
      0,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &escapeHotKeyRef
    )
  }

  private func unregisterEscapeHotKey() {
    if let escapeHotKeyRef {
      UnregisterEventHotKey(escapeHotKeyRef)
      self.escapeHotKeyRef = nil
    }
  }

  private func installEscapeMonitors() {
    removeEscapeMonitors()

    escapeLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard event.keyCode == UInt16(kVK_Escape), self?.isRecording == true else {
        return event
      }
      self?.cancelRecordingForRetry()
      return nil
    }

    escapeGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard event.keyCode == UInt16(kVK_Escape), self?.isRecording == true else { return }
      DispatchQueue.main.async {
        self?.cancelRecordingForRetry()
      }
    }
  }

  private func removeEscapeMonitors() {
    if let escapeLocalMonitor {
      NSEvent.removeMonitor(escapeLocalMonitor)
      self.escapeLocalMonitor = nil
    }
    if let escapeGlobalMonitor {
      NSEvent.removeMonitor(escapeGlobalMonitor)
      self.escapeGlobalMonitor = nil
    }
  }

  private func hotKeyID(from event: EventRef?) -> UInt32 {
    guard let event else { return 0 }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
      event,
      EventParamName(kEventParamDirectObject),
      EventParamType(typeEventHotKeyID),
      nil,
      MemoryLayout<EventHotKeyID>.size,
      nil,
      &hotKeyID
    )
    return status == noErr ? hotKeyID.id : 0
  }

  private func startGlowAnimation() {
    animationTimer?.invalidate()
    animationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      guard let self else { return }
      self.recorder?.updateMeters()
      let averagePower = self.recorder?.averagePower(forChannel: 0) ?? -80
      let normalized = max(0, min(1, CGFloat((averagePower + 50) / 50)))
      self.smoothedAudioLevel = (self.smoothedAudioLevel * 0.68) + (normalized * 0.32)
      self.tabletView.audioLevel = self.smoothedAudioLevel
      self.tabletView.needsDisplay = true
    }
  }

  private func stopGlowAnimation() {
    animationTimer?.invalidate()
    animationTimer = nil
    tabletView.needsDisplay = true
  }

  private func hideTablet(after delay: TimeInterval) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
      guard !self.isRecording else { return }
      self.tabletPanel.orderOut(nil)
    }
  }

  private func setStatus(_ value: String) {
    DispatchQueue.main.async {
      self.statusLabel?.stringValue = value
      self.tabletView?.statusText = value
      self.mainStatusLabel?.stringValue = value
    }
  }

  private func setReadyStatus() {
    setStatus("Ready: \(Preferences.shared.shortcut.title)")
  }

  private func refreshAccessibilityStatus() {
    accessibilityStatusLabel?.stringValue = accessibilityStatusText()
  }

  private func accessibilityStatusText() -> String {
    ensureAccessibilityPermission(prompt: false)
      ? "Auto-paste: Ready"
      : "Auto-paste: Enable Accessibility, then reopen Hushly."
  }

  private func playStartSound() {
    playPopSound()
  }

  private func playStopSound() {
    playPopSound()
  }

  private func playPopSound() {
    guard let popSound else {
      NSSound.beep()
      return
    }

    popSound.stop()
    popSound.currentTime = 0
    popSound.play()
  }

  private func fourCharCode(_ value: String) -> OSType {
    value.utf8.reduce(0) { ($0 << 8) + OSType($1) }
  }
}

final class TabletView: NSView {
  var displayText = "$10k/month" {
    didSet { needsDisplay = true }
  }

  var statusText = "Ready" {
    didSet { needsDisplay = true }
  }

  var isRecording = false {
    didSet { needsDisplay = true }
  }

  var audioLevel: CGFloat = 0 {
    didSet { needsDisplay = true }
  }

  override var mouseDownCanMoveWindow: Bool {
    true
  }

  private lazy var generatedAsset: NSImage? = {
    guard let url = Bundle.main.url(forResource: "tablet-glow", withExtension: "png") else { return nil }
    return NSImage(contentsOf: url)
  }()

  override func draw(_ dirtyRect: NSRect) {
    NSColor.clear.setFill()
    dirtyRect.fill()

    if let generatedAsset {
      generatedAsset.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: isRecording ? 1 : 0.78)
    } else {
      drawFallbackTablet()
    }

    drawGlow()
    drawDisplayText()
    drawWaveform()
  }

  private func drawFallbackTablet() {
    let rect = bounds.insetBy(dx: 6, dy: 6)
    let path = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)
    NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.07, alpha: 0.92).setFill()
    path.fill()
    NSColor(calibratedRed: 0.18, green: 0.87, blue: 1, alpha: 0.75).setStroke()
    path.lineWidth = 1.5
    path.stroke()
  }

  private func drawGlow() {
    let stroke = NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 6), xRadius: 13, yRadius: 13)
    (isRecording
      ? NSColor(calibratedRed: 0.20, green: 0.95, blue: 1, alpha: 0.55)
      : NSColor(calibratedRed: 0.55, green: 0.32, blue: 1, alpha: 0.34)
    ).setStroke()
    stroke.lineWidth = isRecording ? 2 : 1
    stroke.stroke()
  }

  private func drawDisplayText() {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byTruncatingTail

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedRed: 0.10, green: 0.92, blue: 1, alpha: 0.88)
    shadow.shadowBlurRadius = isRecording ? 8 : 4
    shadow.shadowOffset = .zero

    let font = NSFont.systemFont(ofSize: min(16, bounds.height * 0.42), weight: .heavy)
    let attrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: NSColor.white,
      .paragraphStyle: paragraph,
      .shadow: shadow,
    ]

    let textRect = NSRect(x: 24, y: bounds.midY - 10, width: bounds.width - 48, height: 22)
    displayText.draw(in: textRect, withAttributes: attrs)
  }

  private func drawWaveform() {
    let barCount = 12
    let totalWidth: CGFloat = 78
    let startX = bounds.midX - (totalWidth / 2)
    let baseY: CGFloat = 7
    let phase = CGFloat(Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10))

    for index in 0..<barCount {
      let x = startX + CGFloat(index) * (totalWidth / CGFloat(barCount))
      let pulse = (sin((CGFloat(index) * 0.9) + (phase * 10)) + 1) / 2
      let liveHeight = 2 + (audioLevel * 15 * (0.45 + pulse))
      let height = isRecording ? max(2, liveHeight) : 2
      let rect = NSRect(x: x, y: baseY, width: 2.4, height: height)
      let path = NSBezierPath(roundedRect: rect, xRadius: 1.2, yRadius: 1.2)
      NSColor(calibratedRed: 0.18, green: 0.92, blue: 1, alpha: isRecording ? 0.95 : 0.34).setFill()
      path.fill()
    }
  }
}

final class ShortcutCaptureButton: NSButton {
  var onShortcut: ((ShortcutOption) -> Void)?
  var onCancel: (() -> Void)?
  var isCapturingShortcut = false

  override var acceptsFirstResponder: Bool {
    true
  }

  override func keyDown(with event: NSEvent) {
    guard isCapturingShortcut else {
      super.keyDown(with: event)
      return
    }

    if event.keyCode == UInt16(kVK_Escape) {
      isCapturingShortcut = false
      onCancel?()
      return
    }

    let modifiers = carbonModifiers(from: event.modifierFlags)
    let keyCode = UInt32(event.keyCode)
    guard modifiers != 0 || isStandaloneShortcutKey(keyCode) else {
      NSSound.beep()
      return
    }

    let shortcut = ShortcutOption(
      id: "custom-\(keyCode)-\(modifiers)",
      title: shortcutTitle(keyCode: keyCode, modifiers: modifiers, fallbackLabel: event.charactersIgnoringModifiers?.uppercased()),
      keyCode: keyCode,
      modifiers: modifiers
    )
    isCapturingShortcut = false
    onShortcut?(shortcut)
  }
}

final class ShortcutCaptureView: NSView {
  var onShortcut: ((ShortcutOption) -> Void)?
  var onCancel: (() -> Void)?

  override var acceptsFirstResponder: Bool {
    true
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == UInt16(kVK_Escape) {
      onCancel?()
      return
    }

    let modifiers = carbonModifiers(from: event.modifierFlags)
    let keyCode = UInt32(event.keyCode)
    guard modifiers != 0 || isStandaloneShortcutKey(keyCode) else {
      NSSound.beep()
      return
    }

    onShortcut?(
      ShortcutOption(
        id: "custom-\(keyCode)-\(modifiers)",
        title: shortcutTitle(keyCode: keyCode, modifiers: modifiers, fallbackLabel: event.charactersIgnoringModifiers?.uppercased()),
        keyCode: keyCode,
        modifiers: modifiers
      )
    )
  }
}

final class Preferences {
  static let shared = Preferences()

  private let defaults = UserDefaults.standard
  private let tabletTextKey = "tabletText"
  private let shortcutIDKey = "shortcutID"
  private let shortcutKeyCodeKey = "shortcutKeyCode"
  private let shortcutModifiersKey = "shortcutModifiers"
  private let shortcutTitleKey = "shortcutTitle"
  private let apiBaseKey = "apiBase"

  var tabletText: String {
    get {
      let value = defaults.string(forKey: tabletTextKey) ?? "$10k/month"
      return value.isEmpty ? "$10k/month" : value
    }
    set {
      defaults.set(newValue, forKey: tabletTextKey)
    }
  }

  var shortcutID: String {
    get {
      defaults.string(forKey: shortcutIDKey) ?? ShortcutCatalog.defaultOption.id
    }
    set {
      defaults.set(newValue, forKey: shortcutIDKey)
    }
  }

  var shortcut: ShortcutOption {
    get {
      if defaults.object(forKey: shortcutKeyCodeKey) != nil {
        let keyCode = UInt32(defaults.integer(forKey: shortcutKeyCodeKey))
        let modifiers = UInt32(defaults.integer(forKey: shortcutModifiersKey))
        let title = defaults.string(forKey: shortcutTitleKey) ?? shortcutTitle(keyCode: keyCode, modifiers: modifiers)
        return ShortcutOption(id: "custom-\(keyCode)-\(modifiers)", title: title, keyCode: keyCode, modifiers: modifiers)
      }

      return ShortcutCatalog.option(id: shortcutID)
    }
    set {
      defaults.set(Int(newValue.keyCode), forKey: shortcutKeyCodeKey)
      defaults.set(Int(newValue.modifiers), forKey: shortcutModifiersKey)
      defaults.set(newValue.title, forKey: shortcutTitleKey)
    }
  }

  var apiBase: String {
    get {
      normalizedAPIBase(defaults.string(forKey: apiBaseKey) ?? defaultAPIBase)
    }
    set {
      defaults.set(normalizedAPIBase(newValue), forKey: apiBaseKey)
    }
  }
}

struct ShortcutOption {
  let id: String
  let title: String
  let keyCode: UInt32
  let modifiers: UInt32
}

enum ShortcutCatalog {
  static let options = [
    ShortcutOption(id: "controlOptionSpace", title: "Control + Option + Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)),
    ShortcutOption(id: "controlOptionD", title: "Control + Option + D", keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey | optionKey)),
    ShortcutOption(id: "controlShiftSpace", title: "Control + Shift + Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | shiftKey)),
    ShortcutOption(id: "commandShiftH", title: "Command + Shift + H", keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(cmdKey | shiftKey)),
  ]

  static let defaultOption = options[0]

  static func option(id: String) -> ShortcutOption {
    options.first { $0.id == id } ?? defaultOption
  }
}

private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
  let cleanFlags = flags.intersection(.deviceIndependentFlagsMask)
  var modifiers: UInt32 = 0
  if cleanFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
  if cleanFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
  if cleanFlags.contains(.control) { modifiers |= UInt32(controlKey) }
  if cleanFlags.contains(.option) { modifiers |= UInt32(optionKey) }
  return modifiers
}

private func shortcutTitle(keyCode: UInt32, modifiers: UInt32, fallbackLabel: String? = nil) -> String {
  let modifierText = modifierTitle(modifiers)
  var parts: [String] = []
  if !modifierText.isEmpty { parts.append(modifierText) }
  parts.append(keyLabel(keyCode, fallbackLabel: fallbackLabel))
  return parts.joined(separator: " + ")
}

private func modifierTitle(_ modifiers: UInt32) -> String {
  var parts: [String] = []
  if modifiers & UInt32(controlKey) != 0 { parts.append("Control") }
  if modifiers & UInt32(optionKey) != 0 { parts.append("Option") }
  if modifiers & UInt32(shiftKey) != 0 { parts.append("Shift") }
  if modifiers & UInt32(cmdKey) != 0 { parts.append("Command") }
  return parts.joined(separator: " + ")
}

private func isStandaloneShortcutKey(_ keyCode: UInt32) -> Bool {
  let functionKeys: Set<UInt32> = [
    UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4),
    UInt32(kVK_F5), UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8),
    UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12),
    UInt32(kVK_F13), UInt32(kVK_F14), UInt32(kVK_F15), UInt32(kVK_F16),
    UInt32(kVK_F17), UInt32(kVK_F18), UInt32(kVK_F19), UInt32(kVK_F20),
  ]
  return functionKeys.contains(keyCode)
}

private func keyLabel(_ keyCode: UInt32, fallbackLabel: String? = nil) -> String {
  let special: [UInt32: String] = [
    UInt32(kVK_Space): "Space",
    UInt32(kVK_Return): "Return",
    UInt32(kVK_Tab): "Tab",
    UInt32(kVK_Delete): "Delete",
    UInt32(kVK_ForwardDelete): "Forward Delete",
    UInt32(kVK_LeftArrow): "Left Arrow",
    UInt32(kVK_RightArrow): "Right Arrow",
    UInt32(kVK_UpArrow): "Up Arrow",
    UInt32(kVK_DownArrow): "Down Arrow",
    UInt32(kVK_F1): "F1",
    UInt32(kVK_F2): "F2",
    UInt32(kVK_F3): "F3",
    UInt32(kVK_F4): "F4",
    UInt32(kVK_F5): "F5",
    UInt32(kVK_F6): "F6",
    UInt32(kVK_F7): "F7",
    UInt32(kVK_F8): "F8",
    UInt32(kVK_F9): "F9",
    UInt32(kVK_F10): "F10",
    UInt32(kVK_F11): "F11",
    UInt32(kVK_F12): "F12",
    UInt32(kVK_F13): "F13",
    UInt32(kVK_F14): "F14",
    UInt32(kVK_F15): "F15",
    UInt32(kVK_F16): "F16",
    UInt32(kVK_F17): "F17",
    UInt32(kVK_F18): "F18",
    UInt32(kVK_F19): "F19",
    UInt32(kVK_F20): "F20",
  ]
  if let label = special[keyCode] { return label }

  let keys: [UInt32: String] = [
    UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
    UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
    UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
    UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
    UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
    UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
    UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
    UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
    UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
    UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
    UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
    UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
    UInt32(kVK_ANSI_9): "9",
    UInt32(kVK_ANSI_Grave): "`",
    UInt32(kVK_ANSI_Minus): "-",
    UInt32(kVK_ANSI_Equal): "=",
    UInt32(kVK_ANSI_LeftBracket): "[",
    UInt32(kVK_ANSI_RightBracket): "]",
    UInt32(kVK_ANSI_Backslash): "\\",
    UInt32(kVK_ANSI_Semicolon): ";",
    UInt32(kVK_ANSI_Quote): "'",
    UInt32(kVK_ANSI_Comma): ",",
    UInt32(kVK_ANSI_Period): ".",
    UInt32(kVK_ANSI_Slash): "/",
  ]
  if let label = keys[keyCode] { return label }
  if let fallbackLabel, !fallbackLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    return fallbackLabel
  }
  return "Key \(keyCode)"
}

struct TranscriptEntry: Codable {
  let id: String
  let createdAt: Date
  var rawText: String
  var cleanedText: String
  var audioPath: String?
  var status: String
}

final class TranscriptStore {
  static let shared = TranscriptStore()

  private let supportURL: URL
  private let fileURL: URL

  private init() {
    supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Hushly", isDirectory: true)
    try? FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
    fileURL = supportURL.appendingPathComponent("transcripts.json")
  }

  func load() -> [TranscriptEntry] {
    guard let data = try? Data(contentsOf: fileURL) else { return [] }
    return (try? JSONDecoder().decode([TranscriptEntry].self, from: data)) ?? []
  }

  func save(_ entries: [TranscriptEntry]) {
    guard let data = try? JSONEncoder().encode(entries) else { return }
    try? data.write(to: fileURL, options: [.atomic])
  }

  func storeAudio(_ sourceURL: URL) throws -> URL {
    let audioURL = supportURL.appendingPathComponent("Audio", isDirectory: true)
    try FileManager.default.createDirectory(at: audioURL, withIntermediateDirectories: true)
    let destination = audioURL
      .appendingPathComponent("pending-\(UUID().uuidString)")
      .appendingPathExtension("m4a")
    try FileManager.default.copyItem(at: sourceURL, to: destination)
    return destination
  }
}

enum HushlyError: LocalizedError {
  case api(String)

  var errorDescription: String? {
    switch self {
    case .api(let message):
      return message
    }
  }
}

private func normalizedAPIBase(_ raw: String) -> String {
  let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return defaultAPIBase }
  return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
}
