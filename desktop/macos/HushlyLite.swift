import AppKit
import ApplicationServices
import AVFoundation
import AudioToolbox
import Carbon.HIToolbox
import Sparkle

private let defaultAPIBase = "https://hushly.genflos.com"

@main
struct HushlyLiteApp {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, @unchecked Sendable {
  private let updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
  )
  private var tabletPanel: NSPanel!
  private var tabletView: TabletView!
  private var statusLabel: NSTextField!
  private var statusItem: NSStatusItem!
  private var settingsWindow: NSWindow?
  private var tabletTextField: NSTextField?
  private var showTabletTextCheckbox: NSButton?
  private var tabletImageStatusLabel: NSTextField?
  private var tabletShapeControl: NSSegmentedControl?
  private var tabletBorderColorWell: NSColorWell?
  private var tabletTextColorWell: NSColorWell?
  private var tabletTextFontPopup: NSPopUpButton?
  private var tabletTextSizeSlider: NSSlider?
  private var tabletTextXSlider: NSSlider?
  private var tabletTextYSlider: NSSlider?
  private var tabletPreviewHost: NSView?
  private var tabletPreviewView: TabletView?
  private var cropWindow: NSPanel?
  private var cropPreview: TabletCropPreviewView?
  private var cropZoomSlider: NSSlider?
  private var cropXSlider: NSSlider?
  private var cropYSlider: NSSlider?
  private var cropImage: NSImage?
  private var cropShape = TabletShape.rectangle
  private var shortcutButton: NSButton?
  private var shortcutCaptureWindow: NSPanel?
  private var shortcutCaptureMonitor: Any?
  private var shortcutCaptureHintLabel: NSTextField?
  private var apiBaseField: NSTextField?
  private var apiKeyField: NSSecureTextField?
  private var dictionaryPane: NSView?
  private var dictionaryTable: NSTableView?
  private var dictionaryStatusLabel: NSTextField?
  private var addDictionaryButton: NSButton?
  private var removeDictionaryButton: NSButton?
  private var usagePane: NSView?
  private var usageSummaryText: NSTextView?
  private var usageStatusLabel: NSTextField?
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
  private var dictionaryItems: [DictionaryReplacement] = []
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
      showTabletTextCheckbox = nil
      tabletImageStatusLabel = nil
      tabletShapeControl = nil
      tabletBorderColorWell = nil
      tabletTextColorWell = nil
      tabletTextFontPopup = nil
      tabletTextSizeSlider = nil
      tabletTextXSlider = nil
      tabletTextYSlider = nil
      tabletPreviewHost = nil
      tabletPreviewView = nil
      shortcutButton = nil
      apiBaseField = nil
      apiKeyField = nil
      mainStatusLabel = nil
      accessibilityStatusLabel = nil
      tabControl = nil
      settingsPane = nil
      dictionaryPane = nil
      dictionaryTable = nil
      dictionaryStatusLabel = nil
      addDictionaryButton = nil
      removeDictionaryButton = nil
      usagePane = nil
      usageSummaryText = nil
      usageStatusLabel = nil
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
    let checkForUpdatesItem = NSMenuItem(
      title: "Check for Updates...",
      action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
      keyEquivalent: ""
    )
    checkForUpdatesItem.target = updaterController
    appMenu.addItem(checkForUpdatesItem)
    appMenu.addItem(.separator())
    appMenu.addItem(NSMenuItem(title: "Hide Hushly", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
    appMenu.addItem(NSMenuItem(title: "Quit Hushly", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    appMenuItem.submenu = appMenu
    mainMenu.addItem(appMenuItem)

    let editMenuItem = NSMenuItem()
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
    editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
    editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
    editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
    editMenuItem.submenu = editMenu
    mainMenu.addItem(editMenuItem)

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
    applyTabletAppearance()
    content.addSubview(tabletView)

    statusLabel = NSTextField(labelWithString: "Ready")
    statusLabel.frame = NSRect(x: 12, y: 3, width: 192, height: 10)
    statusLabel.textColor = NSColor.white.withAlphaComponent(0.72)
    statusLabel.font = NSFont.systemFont(ofSize: 8, weight: .medium)
    statusLabel.lineBreakMode = .byTruncatingTail
    statusLabel.maximumNumberOfLines = 1
    content.addSubview(statusLabel)

    tabletPanel.contentView = content
    applyTabletAppearance()
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
      self.applyTabletAppearance()
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
    addAPIKeyHeader(to: &request)

    let data = try Data(contentsOf: fileURL)
    let (responseData, response) = try await URLSession.shared.upload(for: request, from: data)
    let json = try decodeAPIResponse(data: responseData, response: response, label: "transcribe")
    return json["transcript"] as? String ?? ""
  }

  private func clean(transcript: String) async throws -> String {
    var request = URLRequest(url: apiURL(path: "/clean"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    addAPIKeyHeader(to: &request)

    var body: [String: Any] = ["text": transcript]
    let dictionary = Preferences.shared.dictionaryEntries.map {
      ["trigger": $0.trigger, "replacement": $0.replacement]
    }
    if !dictionary.isEmpty {
      body["dictionary"] = dictionary
    }

    let payload = try JSONSerialization.data(withJSONObject: body)
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

  private func addAPIKeyHeader(to request: inout URLRequest) {
    let apiKey = Preferences.shared.apiKey
    if !apiKey.isEmpty {
      request.setValue(apiKey, forHTTPHeaderField: "X-Hushly-API-Key")
    }
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
    applyTabletAppearance()
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
    let height: CGFloat = 800
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

    let tabs = NSSegmentedControl(labels: ["Settings", "Dictionary", "Usage", "History"], trackingMode: .selectOne, target: self, action: #selector(switchMainPane))
    tabs.frame = NSRect(x: 24, y: height - 48, width: 410, height: 28)
    tabs.selectedSegment = 0
    content.addSubview(tabs)
    tabControl = tabs

    let paneFrame = NSRect(x: 0, y: 0, width: width, height: height - 64)
    let settingsPane = buildSettingsPane(frame: paneFrame)
    let dictionaryPane = buildDictionaryPane(frame: paneFrame)
    let usagePane = buildUsagePane(frame: paneFrame)
    let historyPane = buildHistoryPane(frame: paneFrame)
    dictionaryPane.isHidden = true
    usagePane.isHidden = true
    historyPane.isHidden = true

    content.addSubview(settingsPane)
    content.addSubview(dictionaryPane)
    content.addSubview(usagePane)
    content.addSubview(historyPane)
    self.settingsPane = settingsPane
    self.dictionaryPane = dictionaryPane
    self.usagePane = usagePane
    self.historyPane = historyPane

    window.contentView = content
    settingsWindow = window
    refreshSettingsFields()
    refreshHistoryUI()
  }

  private func buildSettingsPane(frame: NSRect) -> NSView {
    let content = NSView(frame: frame)

    func addLabel(_ title: String, y: CGFloat, width: CGFloat = 120, x: CGFloat = 32) {
      let label = NSTextField(labelWithString: title)
      label.frame = NSRect(x: x, y: y, width: width, height: 18)
      content.addSubview(label)
    }

    let textLabel = NSTextField(labelWithString: "Tablet text")
    textLabel.frame = NSRect(x: 32, y: 636, width: 120, height: 18)
    content.addSubview(textLabel)

    let textField = NSTextField(string: Preferences.shared.tabletText)
    textField.frame = NSRect(x: 168, y: 630, width: 396, height: 30)
    content.addSubview(textField)
    tabletTextField = textField

    let showText = NSButton(checkboxWithTitle: "Show text on tablet", target: self, action: #selector(tabletAppearanceControlChanged))
    showText.frame = NSRect(x: 168, y: 596, width: 220, height: 24)
    showText.state = Preferences.shared.showTabletText ? .on : .off
    content.addSubview(showText)
    showTabletTextCheckbox = showText

    addLabel("Text color", y: 556)
    let textColorWell = NSColorWell(frame: NSRect(x: 168, y: 548, width: 58, height: 32))
    textColorWell.color = Preferences.shared.tabletTextColor
    textColorWell.target = self
    textColorWell.action = #selector(tabletAppearanceControlChanged)
    content.addSubview(textColorWell)
    tabletTextColorWell = textColorWell

    addLabel("Font", y: 556, width: 44, x: 288)
    let fontPopup = NSPopUpButton(frame: NSRect(x: 344, y: 548, width: 220, height: 32), pullsDown: false)
    for font in TabletTextFont.allCases {
      fontPopup.addItem(withTitle: font.title)
      fontPopup.lastItem?.representedObject = font.rawValue
    }
    fontPopup.selectItem(withTitle: Preferences.shared.tabletTextFont.title)
    fontPopup.target = self
    fontPopup.action = #selector(tabletAppearanceControlChanged)
    content.addSubview(fontPopup)
    tabletTextFontPopup = fontPopup

    addLabel("Text size", y: 514)
    let sizeSlider = NSSlider(value: Preferences.shared.tabletTextSize, minValue: 7, maxValue: 24, target: self, action: #selector(tabletAppearanceControlChanged))
    sizeSlider.frame = NSRect(x: 168, y: 510, width: 396, height: 24)
    sizeSlider.isContinuous = true
    content.addSubview(sizeSlider)
    tabletTextSizeSlider = sizeSlider

    addLabel("Text X", y: 474)
    let xSlider = NSSlider(value: Preferences.shared.tabletTextOffsetX, minValue: -28, maxValue: 28, target: self, action: #selector(tabletAppearanceControlChanged))
    xSlider.frame = NSRect(x: 168, y: 470, width: 150, height: 24)
    xSlider.isContinuous = true
    content.addSubview(xSlider)
    tabletTextXSlider = xSlider

    addLabel("Text Y", y: 474, width: 52, x: 344)
    let ySlider = NSSlider(value: Preferences.shared.tabletTextOffsetY, minValue: -28, maxValue: 28, target: self, action: #selector(tabletAppearanceControlChanged))
    ySlider.frame = NSRect(x: 414, y: 470, width: 150, height: 24)
    ySlider.isContinuous = true
    content.addSubview(ySlider)
    tabletTextYSlider = ySlider

    let imageLabel = NSTextField(labelWithString: "Tablet image")
    imageLabel.frame = NSRect(x: 32, y: 430, width: 120, height: 18)
    content.addSubview(imageLabel)

    let chooseImageButton = NSButton(title: "Choose Image...", target: self, action: #selector(chooseTabletImage))
    chooseImageButton.frame = NSRect(x: 168, y: 424, width: 124, height: 30)
    chooseImageButton.bezelStyle = .rounded
    content.addSubview(chooseImageButton)

    let clearImageButton = NSButton(title: "Clear Image", target: self, action: #selector(clearTabletImage))
    clearImageButton.frame = NSRect(x: 304, y: 424, width: 112, height: 30)
    clearImageButton.bezelStyle = .rounded
    content.addSubview(clearImageButton)

    let imageStatus = NSTextField(labelWithString: tabletImageStatusText())
    imageStatus.frame = NSRect(x: 168, y: 398, width: 220, height: 18)
    imageStatus.font = NSFont.systemFont(ofSize: 11)
    imageStatus.textColor = NSColor.secondaryLabelColor
    imageStatus.lineBreakMode = .byTruncatingMiddle
    content.addSubview(imageStatus)
    tabletImageStatusLabel = imageStatus

    let previewLabel = NSTextField(labelWithString: "Recording preview")
    previewLabel.frame = NSRect(x: 400, y: 386, width: 164, height: 18)
    previewLabel.textColor = NSColor.secondaryLabelColor
    previewLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
    content.addSubview(previewLabel)

    let previewHost = NSView(frame: .zero)
    previewHost.wantsLayer = true
    previewHost.layer?.backgroundColor = NSColor(calibratedWhite: 0.02, alpha: 0.94).cgColor
    previewHost.layer?.masksToBounds = true
    content.addSubview(previewHost)
    tabletPreviewHost = previewHost

    let previewView = TabletView(frame: .zero)
    previewView.isRecording = true
    previewView.audioLevel = 0.72
    previewHost.addSubview(previewView)
    tabletPreviewView = previewView

    let shapeLabel = NSTextField(labelWithString: "Shape")
    shapeLabel.frame = NSRect(x: 32, y: 360, width: 120, height: 18)
    content.addSubview(shapeLabel)

    let shapeControl = NSSegmentedControl(labels: ["Rectangle", "Circle"], trackingMode: .selectOne, target: self, action: #selector(tabletAppearanceControlChanged))
    shapeControl.frame = NSRect(x: 168, y: 354, width: 220, height: 28)
    shapeControl.selectedSegment = Preferences.shared.tabletShape == .circle ? 1 : 0
    content.addSubview(shapeControl)
    tabletShapeControl = shapeControl

    let borderLabel = NSTextField(labelWithString: "Border color")
    borderLabel.frame = NSRect(x: 32, y: 316, width: 120, height: 18)
    content.addSubview(borderLabel)

    let colorWell = NSColorWell(frame: NSRect(x: 168, y: 308, width: 58, height: 32))
    colorWell.color = Preferences.shared.tabletBorderColor
    colorWell.target = self
    colorWell.action = #selector(tabletAppearanceControlChanged)
    content.addSubview(colorWell)
    tabletBorderColorWell = colorWell

    let shortcutLabel = NSTextField(labelWithString: "Shortcut")
    shortcutLabel.frame = NSRect(x: 32, y: 274, width: 120, height: 18)
    content.addSubview(shortcutLabel)

    let shortcutButton = NSButton(title: Preferences.shared.shortcut.title, target: self, action: #selector(beginShortcutCapture))
    shortcutButton.frame = NSRect(x: 168, y: 268, width: 396, height: 32)
    shortcutButton.bezelStyle = .rounded
    content.addSubview(shortcutButton)
    self.shortcutButton = shortcutButton

    let apiLabel = NSTextField(labelWithString: "API base")
    apiLabel.frame = NSRect(x: 32, y: 216, width: 120, height: 18)
    content.addSubview(apiLabel)

    let apiField = NSTextField(string: Preferences.shared.apiBase)
    apiField.frame = NSRect(x: 168, y: 210, width: 396, height: 30)
    content.addSubview(apiField)
    apiBaseField = apiField

    let apiKeyLabel = NSTextField(labelWithString: "API key")
    apiKeyLabel.frame = NSRect(x: 32, y: 174, width: 120, height: 18)
    content.addSubview(apiKeyLabel)

    let keyField = NSSecureTextField(string: Preferences.shared.apiKey)
    keyField.frame = NSRect(x: 168, y: 168, width: 288, height: 30)
    content.addSubview(keyField)
    apiKeyField = keyField

    let pasteKeyButton = NSButton(title: "Paste", target: self, action: #selector(pasteAPIKeyFromClipboard))
    pasteKeyButton.frame = NSRect(x: 468, y: 166, width: 96, height: 32)
    pasteKeyButton.bezelStyle = .rounded
    content.addSubview(pasteKeyButton)

    let accessStatus = NSTextField(labelWithString: accessibilityStatusText())
    accessStatus.frame = NSRect(x: 32, y: 126, width: 532, height: 18)
    accessStatus.textColor = NSColor.secondaryLabelColor
    accessStatus.font = NSFont.systemFont(ofSize: 11)
    accessStatus.lineBreakMode = .byTruncatingTail
    accessStatus.maximumNumberOfLines = 1
    content.addSubview(accessStatus)
    accessibilityStatusLabel = accessStatus

    let mainStatus = NSTextField(labelWithString: "Ready: \(Preferences.shared.shortcut.title)")
    mainStatus.frame = NSRect(x: 32, y: 96, width: 532, height: 18)
    mainStatus.textColor = NSColor.secondaryLabelColor
    mainStatus.font = NSFont.systemFont(ofSize: 12, weight: .medium)
    mainStatus.lineBreakMode = .byTruncatingTail
    mainStatus.maximumNumberOfLines = 1
    content.addSubview(mainStatus)
    mainStatusLabel = mainStatus

    let dictateButton = NSButton(title: "Dictate", target: self, action: #selector(toggleDictation))
    dictateButton.frame = NSRect(x: 360, y: 52, width: 96, height: 32)
    dictateButton.bezelStyle = .rounded
    content.addSubview(dictateButton)

    let saveButton = NSButton(title: "Save", target: self, action: #selector(saveSettings))
    saveButton.frame = NSRect(x: 468, y: 52, width: 96, height: 32)
    saveButton.bezelStyle = .rounded
    content.addSubview(saveButton)

    return content
  }

  private func buildDictionaryPane(frame: NSRect) -> NSView {
    let content = NSView(frame: frame)
    dictionaryItems = Preferences.shared.dictionaryEntries

    let title = NSTextField(labelWithString: "Dictionary")
    title.frame = NSRect(x: 32, y: frame.height - 92, width: 200, height: 22)
    title.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
    content.addSubview(title)

    let leftLabel = NSTextField(labelWithString: "When I say")
    leftLabel.frame = NSRect(x: 44, y: frame.height - 126, width: 220, height: 18)
    leftLabel.textColor = NSColor.secondaryLabelColor
    leftLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
    content.addSubview(leftLabel)

    let rightLabel = NSTextField(labelWithString: "Write this")
    rightLabel.frame = NSRect(x: 302, y: frame.height - 126, width: 220, height: 18)
    rightLabel.textColor = NSColor.secondaryLabelColor
    rightLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
    content.addSubview(rightLabel)

    let scroll = NSScrollView(frame: NSRect(x: 32, y: 86, width: 532, height: frame.height - 240))
    scroll.borderType = .bezelBorder
    scroll.hasVerticalScroller = true
    let table = NSTableView(frame: scroll.bounds)
    table.headerView = nil
    table.rowHeight = 46
    table.intercellSpacing = NSSize(width: 12, height: 8)
    table.delegate = self
    table.dataSource = self
    table.allowsMultipleSelection = false
    table.usesAlternatingRowBackgroundColors = false
    let sayColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("dictionary-trigger"))
    sayColumn.width = 245
    sayColumn.minWidth = 180
    table.addTableColumn(sayColumn)
    let replaceColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("dictionary-replacement"))
    replaceColumn.width = 245
    replaceColumn.minWidth = 180
    table.addTableColumn(replaceColumn)
    scroll.documentView = table
    content.addSubview(scroll)
    dictionaryTable = table

    let example = NSTextField(labelWithString: "Example: Gmail -> my Gmail account")
    example.frame = NSRect(x: 32, y: 58, width: 320, height: 18)
    example.textColor = NSColor.secondaryLabelColor
    example.font = NSFont.systemFont(ofSize: 11)
    content.addSubview(example)

    let addButton = NSButton(title: "+", target: self, action: #selector(addDictionaryRule))
    addButton.frame = NSRect(x: 32, y: 20, width: 36, height: 30)
    addButton.bezelStyle = .texturedRounded
    content.addSubview(addButton)
    addDictionaryButton = addButton

    let removeButton = NSButton(title: "-", target: self, action: #selector(removeDictionaryRule))
    removeButton.frame = NSRect(x: 70, y: 20, width: 36, height: 30)
    removeButton.bezelStyle = .texturedRounded
    content.addSubview(removeButton)
    removeDictionaryButton = removeButton

    let status = NSTextField(labelWithString: dictionaryStatusText())
    status.frame = NSRect(x: 118, y: 28, width: 250, height: 18)
    status.textColor = NSColor.secondaryLabelColor
    status.font = NSFont.systemFont(ofSize: 11)
    status.lineBreakMode = .byTruncatingTail
    content.addSubview(status)
    dictionaryStatusLabel = status

    let saveButton = NSButton(title: "Save Dictionary", target: self, action: #selector(saveDictionary))
    saveButton.frame = NSRect(x: 420, y: 20, width: 144, height: 32)
    saveButton.bezelStyle = .rounded
    content.addSubview(saveButton)

    refreshDictionaryControls()

    return content
  }

  private func buildUsagePane(frame: NSRect) -> NSView {
    let content = NSView(frame: frame)

    let title = NSTextField(labelWithString: "Usage")
    title.frame = NSRect(x: 32, y: frame.height - 92, width: 200, height: 22)
    title.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
    content.addSubview(title)

    let status = NSTextField(labelWithString: usageStatusText())
    status.frame = NSRect(x: 32, y: frame.height - 120, width: 532, height: 18)
    status.textColor = NSColor.secondaryLabelColor
    status.font = NSFont.systemFont(ofSize: 12)
    status.lineBreakMode = .byTruncatingTail
    content.addSubview(status)
    usageStatusLabel = status

    let scroll = NSScrollView(frame: NSRect(x: 32, y: 82, width: 532, height: frame.height - 230))
    scroll.borderType = .bezelBorder
    scroll.hasVerticalScroller = true
    let textView = NSTextView(frame: scroll.bounds)
    textView.isEditable = false
    textView.isSelectable = true
    textView.drawsBackground = false
    textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    textView.textColor = NSColor.labelColor
    textView.textContainerInset = NSSize(width: 8, height: 8)
    textView.string = "Click Refresh to load usage for this API key."
    scroll.documentView = textView
    content.addSubview(scroll)
    usageSummaryText = textView

    let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refreshUsage))
    refreshButton.frame = NSRect(x: 468, y: 26, width: 96, height: 32)
    refreshButton.bezelStyle = .rounded
    content.addSubview(refreshButton)

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
    let selected = tabControl?.selectedSegment ?? 0
    settingsPane?.isHidden = selected != 0
    dictionaryPane?.isHidden = selected != 1
    usagePane?.isHidden = selected != 2
    historyPane?.isHidden = selected != 3
    if selected == 2 {
      refreshUsage()
    } else if selected == 3 {
      refreshHistoryUI()
    }
  }

  private func refreshSettingsFields() {
    tabletTextField?.stringValue = Preferences.shared.tabletText
    showTabletTextCheckbox?.state = Preferences.shared.showTabletText ? .on : .off
    tabletImageStatusLabel?.stringValue = tabletImageStatusText()
    tabletShapeControl?.selectedSegment = Preferences.shared.tabletShape == .circle ? 1 : 0
    tabletBorderColorWell?.color = Preferences.shared.tabletBorderColor
    tabletTextColorWell?.color = Preferences.shared.tabletTextColor
    tabletTextFontPopup?.selectItem(withTitle: Preferences.shared.tabletTextFont.title)
    tabletTextSizeSlider?.doubleValue = Preferences.shared.tabletTextSize
    tabletTextXSlider?.doubleValue = Preferences.shared.tabletTextOffsetX
    tabletTextYSlider?.doubleValue = Preferences.shared.tabletTextOffsetY
    apiBaseField?.stringValue = Preferences.shared.apiBase
    apiKeyField?.stringValue = Preferences.shared.apiKey
    dictionaryStatusLabel?.stringValue = dictionaryStatusText()
    usageStatusLabel?.stringValue = usageStatusText()
    shortcutButton?.title = Preferences.shared.shortcut.title
    refreshAccessibilityStatus()
  }

  private func applyTabletAppearance() {
    configureTabletView(tabletView, recording: isRecording, audioLevel: smoothedAudioLevel)
    configureTabletView(tabletPreviewView, recording: true, audioLevel: 0.72)
    layoutTabletPanel()
    layoutTabletPreview()
  }

  private func configureTabletView(_ view: TabletView?, recording: Bool, audioLevel: CGFloat) {
    view?.displayText = Preferences.shared.tabletText
    view?.showsDisplayText = Preferences.shared.showTabletText
    view?.shape = Preferences.shared.tabletShape
    view?.borderColor = Preferences.shared.tabletBorderColor
    view?.textColor = Preferences.shared.tabletTextColor
    view?.textFont = Preferences.shared.tabletTextFont
    view?.textSize = CGFloat(Preferences.shared.tabletTextSize)
    view?.textOffset = NSPoint(x: Preferences.shared.tabletTextOffsetX, y: Preferences.shared.tabletTextOffsetY)
    view?.customBackgroundImage = customTabletImage()
    view?.isRecording = recording
    view?.audioLevel = audioLevel
  }

  private func customTabletImage() -> NSImage? {
    let path = Preferences.shared.tabletImagePath
    guard !path.isEmpty else { return nil }
    return NSImage(contentsOfFile: path)
  }

  private func tabletImageStatusText() -> String {
    let path = Preferences.shared.tabletImagePath
    guard !path.isEmpty else { return "Using default glowing tablet" }
    return "Using custom image: \(URL(fileURLWithPath: path).lastPathComponent)"
  }

  private func selectedTabletShape() -> TabletShape {
    tabletShapeControl?.selectedSegment == 1 ? .circle : .rectangle
  }

  private func selectedTabletTextFont() -> TabletTextFont {
    guard
      let raw = tabletTextFontPopup?.selectedItem?.representedObject as? String,
      let font = TabletTextFont(rawValue: raw)
    else {
      return Preferences.shared.tabletTextFont
    }
    return font
  }

  private func layoutTabletPanel() {
    guard let tabletPanel, let content = tabletPanel.contentView else { return }
    let shape = Preferences.shared.tabletShape
    let size = shape.panelSize
    let origin = tabletPanel.frame.origin
    content.frame = NSRect(origin: .zero, size: size)
    content.layer?.backgroundColor = NSColor.clear.cgColor
    content.layer?.cornerRadius = shape == .circle ? size.width / 2 : 13
    tabletView?.frame = shape.tabletFrame
    statusLabel?.isHidden = shape == .circle
    statusLabel?.frame = NSRect(x: 12, y: 3, width: size.width - 24, height: 10)
    tabletPanel.setContentSize(size)
    tabletPanel.setFrameOrigin(origin)
  }

  private func layoutTabletPreview() {
    guard let host = tabletPreviewHost, let preview = tabletPreviewView else { return }

    let shape = Preferences.shared.tabletShape
    let slot = NSRect(x: 396, y: 306, width: 180, height: 78)
    let size = shape.previewPanelSize
    host.frame = NSRect(
      x: slot.midX - (size.width / 2),
      y: slot.midY - (size.height / 2),
      width: size.width,
      height: size.height
    )
    host.layer?.cornerRadius = shape == .circle ? size.width / 2 : 12
    preview.frame = shape.previewTabletFrame
    preview.needsDisplay = true
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
    "Storage: local on this Mac. VPS sync: not connected in the desktop app."
  }

  private func dictionaryStatusText() -> String {
    let count = dictionaryItems.filter {
      !$0.trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !$0.replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }.count
    return count == 1 ? "1 dictionary rule saved" : "\(count) dictionary rules saved"
  }

  private func usageStatusText() -> String {
    Preferences.shared.apiKey.isEmpty ? "Add an API key in Settings." : "Usage for saved API key."
  }

  @objc private func saveDictionary() {
    settingsWindow?.makeFirstResponder(nil)
    dictionaryItems = dictionaryItems.filter {
      !$0.trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !$0.replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    Preferences.shared.dictionaryEntries = dictionaryItems
    dictionaryTable?.reloadData()
    dictionaryStatusLabel?.stringValue = dictionaryStatusText()
    refreshDictionaryControls()
    setStatus("Dictionary saved")
  }

  @objc private func addDictionaryRule() {
    dictionaryItems.append(DictionaryReplacement(trigger: "", replacement: ""))
    dictionaryTable?.reloadData()
    let row = dictionaryItems.count - 1
    dictionaryTable?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    DispatchQueue.main.async {
      self.dictionaryTable?.editColumn(0, row: row, with: nil, select: true)
    }
    refreshDictionaryControls()
  }

  @objc private func removeDictionaryRule() {
    guard let table = dictionaryTable else { return }
    let selected = table.selectedRow >= 0 ? table.selectedRow : dictionaryItems.count - 1
    guard selected >= 0, selected < dictionaryItems.count else { return }
    dictionaryItems.remove(at: selected)
    table.reloadData()
    if !dictionaryItems.isEmpty {
      let nextRow = min(selected, dictionaryItems.count - 1)
      table.selectRowIndexes(IndexSet(integer: nextRow), byExtendingSelection: false)
    }
    refreshDictionaryControls()
  }

  private func refreshDictionaryControls() {
    removeDictionaryButton?.isEnabled = !dictionaryItems.isEmpty
    dictionaryStatusLabel?.stringValue = dictionaryStatusText()
  }

  @objc private func refreshUsage() {
    usageStatusLabel?.stringValue = usageStatusText()
    guard !Preferences.shared.apiKey.isEmpty else {
      usageSummaryText?.string = "No API key saved."
      return
    }

    usageSummaryText?.string = "Loading..."
    Task { [weak self] in
      await self?.loadUsageSummary()
    }
  }

  private func loadUsageSummary() async {
    do {
      var request = URLRequest(url: apiURL(path: "/usage-summary"), cachePolicy: .reloadIgnoringLocalCacheData)
      request.httpMethod = "GET"
      request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
      request.setValue(localTodayStartISO(), forHTTPHeaderField: "X-Hushly-Today-Start")
      addAPIKeyHeader(to: &request)
      let (data, response) = try await URLSession.shared.data(for: request)
      let json = try decodeAPIResponse(data: data, response: response, label: "usage")
      let text = formatUsageSummary(json)
      DispatchQueue.main.async {
        self.usageSummaryText?.string = text
        self.usageStatusLabel?.stringValue = "Usage loaded"
      }
    } catch {
      DispatchQueue.main.async {
        self.usageSummaryText?.string = error.localizedDescription
        self.usageStatusLabel?.stringValue = "Usage failed"
      }
    }
  }

  private func formatUsageSummary(_ json: [String: Any]) -> String {
    let identity = json["identity"] as? [String: Any] ?? [:]
    let label = (identity["label"] as? String) ?? (identity["email"] as? String) ?? "Current key"
    let tag = identity["tag"] as? String
    let today = json["today"] as? [String: Any] ?? [:]
    let month = json["last30d"] as? [String: Any] ?? [:]
    let updatedAt = json["updatedAt"] as? String

    var lines = ["Identity: \(label)"]
    if let tag, !tag.isEmpty {
      lines.append("Tag: \(tag)")
    }
    if let updatedAt {
      lines.append("Updated: \(updatedAt)")
    }
    lines.append("")
    lines.append("Today")
    lines.append("  Requests: \(intValue(today["requests"]))")
    lines.append("  Transcriptions: \(intValue(today["transcriptions"]))")
    lines.append("  Cleanups: \(intValue(today["cleanups"]))")
    lines.append("  Errors: \(intValue(today["errors"]))")
    lines.append("  Audio uploaded: \(byteString(intValue(today["audioBytes"])))")
    lines.append("")
    lines.append("Last 30 days")
    lines.append("  Requests: \(intValue(month["requests"]))")
    lines.append("  Transcriptions: \(intValue(month["transcriptions"]))")
    lines.append("  Cleanups: \(intValue(month["cleanups"]))")
    lines.append("  Errors: \(intValue(month["errors"]))")
    lines.append("  Audio uploaded: \(byteString(intValue(month["audioBytes"])))")
    return lines.joined(separator: "\n")
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
    if tableView === dictionaryTable {
      return dictionaryItems.count
    }
    return historyItems.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    if tableView === dictionaryTable {
      return dictionaryCell(tableView, tableColumn: tableColumn, row: row)
    }

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
    if notification.object as? NSTableView === dictionaryTable {
      refreshDictionaryControls()
    } else {
      refreshHistoryDetail()
    }
  }

  private func dictionaryCell(_ tableView: NSTableView, tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard row >= 0, row < dictionaryItems.count else { return nil }
    let columnID = tableColumn?.identifier.rawValue ?? "dictionary-trigger"
    let cellID = NSUserInterfaceItemIdentifier(columnID)
    let field = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTextField ?? NSTextField(string: "")
    field.identifier = cellID
    field.delegate = self
    field.tag = row
    field.isEditable = true
    field.isBordered = true
    field.isBezeled = true
    field.bezelStyle = .roundedBezel
    field.drawsBackground = true
    field.backgroundColor = NSColor.controlBackgroundColor
    field.font = NSFont.systemFont(ofSize: 13)
    field.frame = NSRect(x: 6, y: 7, width: max(40, (tableColumn?.width ?? 240) - 12), height: 30)
    field.autoresizingMask = [.width]
    field.lineBreakMode = .byTruncatingTail

    if columnID == "dictionary-replacement" {
      field.placeholderString = "my Gmail account"
      field.stringValue = dictionaryItems[row].replacement
    } else {
      field.placeholderString = "Gmail"
      field.stringValue = dictionaryItems[row].trigger
    }
    return field
  }

  func controlTextDidEndEditing(_ obj: Notification) {
    guard let field = obj.object as? NSTextField else { return }
    let row = field.tag
    guard row >= 0, row < dictionaryItems.count else { return }

    switch field.identifier?.rawValue {
    case "dictionary-replacement":
      dictionaryItems[row].replacement = field.stringValue
    case "dictionary-trigger":
      dictionaryItems[row].trigger = field.stringValue
    default:
      return
    }
    refreshDictionaryControls()
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

  @objc private func tabletAppearanceControlChanged() {
    Preferences.shared.showTabletText = showTabletTextCheckbox?.state == .on
    Preferences.shared.tabletShape = selectedTabletShape()
    if let color = tabletBorderColorWell?.color {
      Preferences.shared.tabletBorderColor = color
    }
    if let color = tabletTextColorWell?.color {
      Preferences.shared.tabletTextColor = color
    }
    Preferences.shared.tabletTextFont = selectedTabletTextFont()
    Preferences.shared.tabletTextSize = tabletTextSizeSlider?.doubleValue ?? Preferences.shared.tabletTextSize
    Preferences.shared.tabletTextOffsetX = tabletTextXSlider?.doubleValue ?? Preferences.shared.tabletTextOffsetX
    Preferences.shared.tabletTextOffsetY = tabletTextYSlider?.doubleValue ?? Preferences.shared.tabletTextOffsetY
    applyTabletAppearance()
    refreshSettingsFields()
    setStatus("Tablet appearance updated")
  }

  @objc private func chooseTabletImage() {
    guard let settingsWindow else { return }

    let panel = NSOpenPanel()
    panel.title = "Choose Tablet Background"
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.beginSheetModal(for: settingsWindow) { [weak self] response in
      guard let self, response == .OK, let url = panel.url else { return }
      guard ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()) else {
        self.setStatus("Choose a PNG or JPEG image")
        return
      }
      guard let image = NSImage(contentsOf: url) else {
        self.setStatus("Image import failed")
        return
      }
      self.showCropWindow(for: image, shape: self.selectedTabletShape())
    }
  }

  @objc private func clearTabletImage() {
    Preferences.shared.tabletImagePath = ""
    try? TabletAssetStore.shared.clearBackground()
    applyTabletAppearance()
    refreshSettingsFields()
    setStatus("Tablet image cleared")
  }

  private func showCropWindow(for image: NSImage, shape: TabletShape) {
    cropWindow?.close()
    cropImage = image
    cropShape = shape
    cropZoomSlider = nil
    cropXSlider = nil
    cropYSlider = nil

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 430),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    panel.title = "Crop Tablet Image"
    panel.isReleasedWhenClosed = false
    panel.isRestorable = false

    let content = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 430))
    let title = NSTextField(labelWithString: "Crop image")
    title.frame = NSRect(x: 24, y: 386, width: 472, height: 22)
    title.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
    content.addSubview(title)

    let previewFrame = shape == .circle
      ? NSRect(x: 170, y: 154, width: 180, height: 180)
      : NSRect(x: 74, y: 190, width: 372, height: 120)
    let preview = TabletCropPreviewView(frame: previewFrame)
    preview.image = image
    preview.shape = shape
    preview.borderColor = Preferences.shared.tabletBorderColor
    content.addSubview(preview)
    cropPreview = preview

    cropZoomSlider = addCropSlider(to: content, title: "Zoom", y: 112, min: 1, max: 3, value: 1)
    cropXSlider = addCropSlider(to: content, title: "Horizontal", y: 78, min: -1, max: 1, value: 0)
    cropYSlider = addCropSlider(to: content, title: "Vertical", y: 44, min: -1, max: 1, value: 0)

    let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelCropImage))
    cancelButton.frame = NSRect(x: 304, y: 10, width: 84, height: 28)
    cancelButton.bezelStyle = .rounded
    content.addSubview(cancelButton)

    let useButton = NSButton(title: "Use Image", target: self, action: #selector(confirmCropImage))
    useButton.frame = NSRect(x: 400, y: 10, width: 96, height: 28)
    useButton.bezelStyle = .rounded
    content.addSubview(useButton)

    panel.contentView = content
    cropWindow = panel
    panel.center()
    if let settingsWindow {
      settingsWindow.beginSheet(panel)
    } else {
      panel.makeKeyAndOrderFront(nil)
    }
  }

  private func addCropSlider(to content: NSView, title: String, y: CGFloat, min: Double, max: Double, value: Double) -> NSSlider {
    let label = NSTextField(labelWithString: title)
    label.frame = NSRect(x: 24, y: y + 4, width: 88, height: 18)
    content.addSubview(label)

    let slider = NSSlider(value: value, minValue: min, maxValue: max, target: self, action: #selector(cropSliderChanged))
    slider.frame = NSRect(x: 120, y: y, width: 376, height: 24)
    content.addSubview(slider)
    return slider
  }

  @objc private func cropSliderChanged() {
    cropPreview?.zoom = CGFloat(cropZoomSlider?.doubleValue ?? 1)
    cropPreview?.offsetX = CGFloat(cropXSlider?.doubleValue ?? 0)
    cropPreview?.offsetY = CGFloat(cropYSlider?.doubleValue ?? 0)
  }

  @objc private func cancelCropImage() {
    closeCropWindow()
  }

  @objc private func confirmCropImage() {
    guard let image = cropImage else {
      closeCropWindow()
      return
    }

    do {
      let croppedURL = try TabletAssetStore.shared.storeCroppedBackground(
        image: image,
        shape: cropShape,
        zoom: CGFloat(cropZoomSlider?.doubleValue ?? 1),
        offsetX: CGFloat(cropXSlider?.doubleValue ?? 0),
        offsetY: CGFloat(cropYSlider?.doubleValue ?? 0)
      )
      Preferences.shared.tabletImagePath = croppedURL.path
      Preferences.shared.tabletShape = cropShape
      applyTabletAppearance()
      refreshSettingsFields()
      setStatus("Tablet image updated")
    } catch {
      setStatus("Image import failed")
    }
    closeCropWindow()
  }

  private func closeCropWindow() {
    guard let cropWindow else { return }
    if let sheetParent = cropWindow.sheetParent {
      sheetParent.endSheet(cropWindow)
    }
    cropWindow.close()
    self.cropWindow = nil
    cropPreview = nil
    cropZoomSlider = nil
    cropXSlider = nil
    cropYSlider = nil
    cropImage = nil
  }

  @objc private func saveSettings() {
    if let text = tabletTextField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
      Preferences.shared.tabletText = text
    }

    Preferences.shared.showTabletText = showTabletTextCheckbox?.state == .on
    Preferences.shared.tabletShape = selectedTabletShape()
    if let color = tabletBorderColorWell?.color {
      Preferences.shared.tabletBorderColor = color
    }
    if let color = tabletTextColorWell?.color {
      Preferences.shared.tabletTextColor = color
    }
    Preferences.shared.tabletTextFont = selectedTabletTextFont()
    Preferences.shared.tabletTextSize = tabletTextSizeSlider?.doubleValue ?? Preferences.shared.tabletTextSize
    Preferences.shared.tabletTextOffsetX = tabletTextXSlider?.doubleValue ?? Preferences.shared.tabletTextOffsetX
    Preferences.shared.tabletTextOffsetY = tabletTextYSlider?.doubleValue ?? Preferences.shared.tabletTextOffsetY

    if let apiBase = apiBaseField?.stringValue {
      Preferences.shared.apiBase = apiBase
    }

    if let apiKey = apiKeyField?.stringValue {
      Preferences.shared.apiKey = apiKey
    }

    applyTabletAppearance()
    setStatus("Settings saved")
    refreshSettingsFields()
  }

  @objc private func pasteAPIKeyFromClipboard() {
    let value = NSPasteboard.general.string(forType: .string)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !value.isEmpty else {
      setStatus("Clipboard has no API key")
      return
    }
    apiKeyField?.stringValue = value
    Preferences.shared.apiKey = value
    refreshSettingsFields()
    setStatus("API key pasted and saved")
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

enum TabletShape: String {
  case rectangle
  case circle

  var panelSize: NSSize {
    switch self {
    case .rectangle:
      return NSSize(width: 216, height: 50)
    case .circle:
      return NSSize(width: 78, height: 78)
    }
  }

  var tabletFrame: NSRect {
    switch self {
    case .rectangle:
      return NSRect(x: 8, y: 14, width: 200, height: 31)
    case .circle:
      return NSRect(x: 8, y: 8, width: 62, height: 62)
    }
  }

  var cropPixelSize: NSSize {
    switch self {
    case .rectangle:
      return NSSize(width: 1200, height: 186)
    case .circle:
      return NSSize(width: 512, height: 512)
    }
  }

  var previewPanelSize: NSSize {
    switch self {
    case .rectangle:
      return NSSize(width: 180, height: 42)
    case .circle:
      return NSSize(width: 78, height: 78)
    }
  }

  var previewTabletFrame: NSRect {
    switch self {
    case .rectangle:
      return NSRect(x: 7, y: 8, width: 166, height: 26)
    case .circle:
      return NSRect(x: 8, y: 8, width: 62, height: 62)
    }
  }
}

enum TabletTextFont: String, CaseIterable {
  case systemHeavy
  case systemMedium
  case roundedHeavy
  case monospacedBold
  case serifBold

  var title: String {
    switch self {
    case .systemHeavy:
      return "System Heavy"
    case .systemMedium:
      return "System Medium"
    case .roundedHeavy:
      return "Rounded Heavy"
    case .monospacedBold:
      return "Monospaced Bold"
    case .serifBold:
      return "Serif Bold"
    }
  }

  func font(ofSize size: CGFloat) -> NSFont {
    switch self {
    case .systemHeavy:
      return NSFont.systemFont(ofSize: size, weight: .heavy)
    case .systemMedium:
      return NSFont.systemFont(ofSize: size, weight: .medium)
    case .roundedHeavy:
      let base = NSFont.systemFont(ofSize: size, weight: .heavy)
      if let descriptor = base.fontDescriptor.withDesign(.rounded),
        let rounded = NSFont(descriptor: descriptor, size: size)
      {
        return rounded
      }
      return base
    case .monospacedBold:
      return NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
    case .serifBold:
      return NSFont(name: "Georgia-Bold", size: size) ?? NSFont.systemFont(ofSize: size, weight: .bold)
    }
  }
}

final class TabletView: NSView {
  var displayText = "$10k/month" {
    didSet { needsDisplay = true }
  }

  var shape = TabletShape.rectangle {
    didSet { needsDisplay = true }
  }

  var borderColor = NSColor(calibratedRed: 0.18, green: 0.92, blue: 1, alpha: 1) {
    didSet { needsDisplay = true }
  }

  var textColor = NSColor.white {
    didSet { needsDisplay = true }
  }

  var textFont = TabletTextFont.systemHeavy {
    didSet { needsDisplay = true }
  }

  var textSize: CGFloat = 16 {
    didSet { needsDisplay = true }
  }

  var textOffset = NSPoint(x: 0, y: 0) {
    didSet { needsDisplay = true }
  }

  var showsDisplayText = true {
    didSet { needsDisplay = true }
  }

  var customBackgroundImage: NSImage? {
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

    let clipPath = shapePath(in: bounds.insetBy(dx: 2, dy: 2))
    NSGraphicsContext.saveGraphicsState()
    clipPath.addClip()
    if let customBackgroundImage {
      customBackgroundImage.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: isRecording ? 1 : 0.88)
    } else if let generatedAsset {
      generatedAsset.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: isRecording ? 1 : 0.78)
    } else {
      drawFallbackFill(in: bounds)
    }
    NSGraphicsContext.restoreGraphicsState()

    drawGlow()
    if showsDisplayText {
      drawDisplayText()
    }
    drawWaveform()
  }

  private func drawFallbackFill(in rect: NSRect) {
    NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.07, alpha: 0.92).setFill()
    rect.fill()
  }

  private func drawGlow() {
    let stroke = shapePath(in: bounds.insetBy(dx: 3, dy: 3))
    borderColor.withAlphaComponent(isRecording ? 0.72 : 0.46).setStroke()
    stroke.lineWidth = isRecording ? 2 : 1
    stroke.stroke()
  }

  private func drawDisplayText() {
    let cleanText = displayText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanText.isEmpty else { return }

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byTruncatingTail

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedRed: 0.10, green: 0.92, blue: 1, alpha: 0.88)
    shadow.shadowBlurRadius = isRecording ? 8 : 4
    shadow.shadowOffset = .zero

    let horizontalInset: CGFloat = shape == .circle ? 9 : 18
    let maxRect = bounds.insetBy(dx: horizontalInset, dy: shape == .circle ? 15 : 5)
    let availableHeight: CGFloat = shape == .circle ? min(24, maxRect.height) : min(20, maxRect.height)
    let requestedSize = min(max(textSize, 7), shape == .circle ? 24 : 22)
    let font = fittedFont(for: cleanText, requestedSize: requestedSize, maxSize: NSSize(width: maxRect.width, height: availableHeight))
    let attrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: textColor,
      .paragraphStyle: paragraph,
      .shadow: shadow,
    ]

    let measured = (cleanText as NSString).size(withAttributes: attrs)
    let baselineCenterY = bounds.midY + (shape == .circle ? 8 : 5)
    let unclamped = NSRect(
      x: maxRect.midX - (maxRect.width / 2) + textOffset.x,
      y: baselineCenterY - (availableHeight / 2) + textOffset.y,
      width: maxRect.width,
      height: max(availableHeight, measured.height + 2)
    )
    let textRect = clamp(unclamped, inside: maxRect)
    (cleanText as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
  }

  private func fittedFont(for text: String, requestedSize: CGFloat, maxSize: NSSize) -> NSFont {
    let minSize: CGFloat = 7
    var size = requestedSize
    while size > minSize {
      let font = textFont.font(ofSize: size)
      let measured = (text as NSString).size(withAttributes: [.font: font])
      if measured.width <= maxSize.width && measured.height <= maxSize.height {
        return font
      }
      size -= 0.5
    }
    return textFont.font(ofSize: minSize)
  }

  private func clamp(_ rect: NSRect, inside bounds: NSRect) -> NSRect {
    let width = min(rect.width, bounds.width)
    let height = min(rect.height, bounds.height)
    let minX = bounds.minX
    let maxX = bounds.maxX - width
    let minY = bounds.minY
    let maxY = bounds.maxY - height
    let x = min(max(rect.origin.x, minX), maxX)
    let y = min(max(rect.origin.y, minY), maxY)
    return NSRect(x: x, y: y, width: width, height: height)
  }

  private func drawWaveform() {
    let barCount = 12
    let totalWidth: CGFloat = shape == .circle ? 38 : 78
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

  private func shapePath(in rect: NSRect) -> NSBezierPath {
    switch shape {
    case .rectangle:
      return NSBezierPath(roundedRect: rect, xRadius: min(16, rect.height / 2), yRadius: min(16, rect.height / 2))
    case .circle:
      let diameter = min(rect.width, rect.height)
      let circleRect = NSRect(x: rect.midX - diameter / 2, y: rect.midY - diameter / 2, width: diameter, height: diameter)
      return NSBezierPath(ovalIn: circleRect)
    }
  }
}

final class TabletCropPreviewView: NSView {
  var image: NSImage? {
    didSet { needsDisplay = true }
  }

  var shape = TabletShape.rectangle {
    didSet { needsDisplay = true }
  }

  var borderColor = NSColor(calibratedRed: 0.18, green: 0.92, blue: 1, alpha: 1) {
    didSet { needsDisplay = true }
  }

  var zoom: CGFloat = 1 {
    didSet { needsDisplay = true }
  }

  var offsetX: CGFloat = 0 {
    didSet { needsDisplay = true }
  }

  var offsetY: CGFloat = 0 {
    didSet { needsDisplay = true }
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor(calibratedWhite: 0.04, alpha: 1).setFill()
    dirtyRect.fill()

    let path = shapePath(in: bounds.insetBy(dx: 2, dy: 2))
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSColor.black.setFill()
    bounds.fill()

    if let image {
      let sourceRect = TabletAssetStore.cropRect(
        for: image.size,
        targetAspect: bounds.width / bounds.height,
        zoom: zoom,
        offsetX: offsetX,
        offsetY: offsetY
      )
      image.draw(in: bounds, from: sourceRect, operation: .sourceOver, fraction: 1)
    }
    NSGraphicsContext.restoreGraphicsState()

    borderColor.withAlphaComponent(0.8).setStroke()
    path.lineWidth = 2
    path.stroke()
  }

  private func shapePath(in rect: NSRect) -> NSBezierPath {
    switch shape {
    case .rectangle:
      return NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18)
    case .circle:
      let diameter = min(rect.width, rect.height)
      let circleRect = NSRect(x: rect.midX - diameter / 2, y: rect.midY - diameter / 2, width: diameter, height: diameter)
      return NSBezierPath(ovalIn: circleRect)
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
  private let showTabletTextKey = "showTabletText"
  private let tabletImagePathKey = "tabletImagePath"
  private let tabletShapeKey = "tabletShape"
  private let tabletBorderColorKey = "tabletBorderColor"
  private let tabletTextColorKey = "tabletTextColor"
  private let tabletTextFontKey = "tabletTextFont"
  private let tabletTextSizeKey = "tabletTextSize"
  private let tabletTextOffsetXKey = "tabletTextOffsetX"
  private let tabletTextOffsetYKey = "tabletTextOffsetY"
  private let shortcutIDKey = "shortcutID"
  private let shortcutKeyCodeKey = "shortcutKeyCode"
  private let shortcutModifiersKey = "shortcutModifiers"
  private let shortcutTitleKey = "shortcutTitle"
  private let apiBaseKey = "apiBase"
  private let apiKeyKey = "apiKey"
  private let dictionaryTextKey = "dictionaryText"

  var tabletText: String {
    get {
      let value = defaults.string(forKey: tabletTextKey) ?? "$10k/month"
      return value.isEmpty ? "$10k/month" : value
    }
    set {
      defaults.set(newValue, forKey: tabletTextKey)
    }
  }

  var showTabletText: Bool {
    get {
      defaults.object(forKey: showTabletTextKey) == nil ? true : defaults.bool(forKey: showTabletTextKey)
    }
    set {
      defaults.set(newValue, forKey: showTabletTextKey)
    }
  }

  var tabletImagePath: String {
    get {
      defaults.string(forKey: tabletImagePathKey) ?? ""
    }
    set {
      defaults.set(newValue, forKey: tabletImagePathKey)
    }
  }

  var tabletShape: TabletShape {
    get {
      TabletShape(rawValue: defaults.string(forKey: tabletShapeKey) ?? "") ?? .rectangle
    }
    set {
      defaults.set(newValue.rawValue, forKey: tabletShapeKey)
    }
  }

  var tabletBorderColor: NSColor {
    get {
      colorFromHex(defaults.string(forKey: tabletBorderColorKey) ?? "#2EEAFF")
    }
    set {
      defaults.set(hexFromColor(newValue), forKey: tabletBorderColorKey)
    }
  }

  var tabletTextColor: NSColor {
    get {
      colorFromHex(defaults.string(forKey: tabletTextColorKey) ?? "#FFFFFF", fallback: NSColor.white)
    }
    set {
      defaults.set(hexFromColor(newValue), forKey: tabletTextColorKey)
    }
  }

  var tabletTextFont: TabletTextFont {
    get {
      TabletTextFont(rawValue: defaults.string(forKey: tabletTextFontKey) ?? "") ?? .systemHeavy
    }
    set {
      defaults.set(newValue.rawValue, forKey: tabletTextFontKey)
    }
  }

  var tabletTextSize: Double {
    get {
      let value = defaults.object(forKey: tabletTextSizeKey) == nil ? 16 : defaults.double(forKey: tabletTextSizeKey)
      return min(max(value, 7), 24)
    }
    set {
      defaults.set(min(max(newValue, 7), 24), forKey: tabletTextSizeKey)
    }
  }

  var tabletTextOffsetX: Double {
    get {
      min(max(defaults.double(forKey: tabletTextOffsetXKey), -28), 28)
    }
    set {
      defaults.set(min(max(newValue, -28), 28), forKey: tabletTextOffsetXKey)
    }
  }

  var tabletTextOffsetY: Double {
    get {
      min(max(defaults.double(forKey: tabletTextOffsetYKey), -28), 28)
    }
    set {
      defaults.set(min(max(newValue, -28), 28), forKey: tabletTextOffsetYKey)
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

  var apiKey: String {
    get {
      defaults.string(forKey: apiKeyKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    set {
      defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: apiKeyKey)
    }
  }

  var dictionaryText: String {
    get {
      defaults.string(forKey: dictionaryTextKey) ?? ""
    }
    set {
      defaults.set(newValue, forKey: dictionaryTextKey)
    }
  }

  var dictionaryEntries: [DictionaryReplacement] {
    get {
      parseDictionaryEntries(dictionaryText)
    }
    set {
      dictionaryText = serializeDictionaryEntries(newValue)
    }
  }
}

struct DictionaryReplacement {
  var trigger: String
  var replacement: String
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

private func colorFromHex(_ value: String, fallback: NSColor = NSColor(calibratedRed: 0.18, green: 0.92, blue: 1, alpha: 1)) -> NSColor {
  let cleaned = value.trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespacesAndNewlines))
  guard cleaned.count == 6, let intValue = Int(cleaned, radix: 16) else {
    return fallback
  }

  let red = CGFloat((intValue >> 16) & 0xFF) / 255
  let green = CGFloat((intValue >> 8) & 0xFF) / 255
  let blue = CGFloat(intValue & 0xFF) / 255
  return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
}

private func hexFromColor(_ color: NSColor) -> String {
  let converted = color.usingColorSpace(.deviceRGB) ?? color
  let red = Int(round(converted.redComponent * 255))
  let green = Int(round(converted.greenComponent * 255))
  let blue = Int(round(converted.blueComponent * 255))
  return String(format: "#%02X%02X%02X", red, green, blue)
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

final class TabletAssetStore {
  static let shared = TabletAssetStore()

  private let supportURL: URL
  private let backgroundURL: URL

  private init() {
    supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Hushly", isDirectory: true)
    try? FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
    backgroundURL = supportURL.appendingPathComponent("tablet-background.png")
  }

  func storeCroppedBackground(
    image: NSImage,
    shape: TabletShape,
    zoom: CGFloat,
    offsetX: CGFloat,
    offsetY: CGFloat
  ) throws -> URL {
    let size = shape.cropPixelSize
    let rep = try croppedPNGRepresentation(
      from: image,
      width: Int(size.width),
      height: Int(size.height),
      zoom: zoom,
      offsetX: offsetX,
      offsetY: offsetY
    )
    try rep.write(to: backgroundURL, options: [.atomic])
    return backgroundURL
  }

  func clearBackground() throws {
    if FileManager.default.fileExists(atPath: backgroundURL.path) {
      try FileManager.default.removeItem(at: backgroundURL)
    }
  }

  private func croppedPNGRepresentation(
    from image: NSImage,
    width: Int,
    height: Int,
    zoom: CGFloat,
    offsetX: CGFloat,
    offsetY: CGFloat
  ) throws -> Data {
    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    else {
      throw HushlyError.api("Could not create image canvas")
    }

    let targetRect = NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
    let sourceRect = Self.cropRect(
      for: image.size,
      targetAspect: targetRect.width / targetRect.height,
      zoom: zoom,
      offsetX: offsetX,
      offsetY: offsetY
    )

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.clear.setFill()
    targetRect.fill()
    image.draw(in: targetRect, from: sourceRect, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
      throw HushlyError.api("Could not encode image")
    }
    return data
  }

  static func cropRect(for imageSize: NSSize, targetAspect: CGFloat, zoom: CGFloat, offsetX: CGFloat, offsetY: CGFloat) -> NSRect {
    guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
    let sourceAspect = imageSize.width / imageSize.height
    let cleanZoom = max(1, min(3, zoom))
    let cleanOffsetX = max(-1, min(1, offsetX))
    let cleanOffsetY = max(-1, min(1, offsetY))
    let baseSize: NSSize

    if sourceAspect > targetAspect {
      let width = imageSize.height * targetAspect
      baseSize = NSSize(width: width, height: imageSize.height)
    } else {
      let height = imageSize.width / targetAspect
      baseSize = NSSize(width: imageSize.width, height: height)
    }

    let croppedSize = NSSize(width: baseSize.width / cleanZoom, height: baseSize.height / cleanZoom)
    let maxX = max(0, (imageSize.width - croppedSize.width) / 2)
    let maxY = max(0, (imageSize.height - croppedSize.height) / 2)
    let origin = NSPoint(
      x: ((imageSize.width - croppedSize.width) / 2) + (cleanOffsetX * maxX),
      y: ((imageSize.height - croppedSize.height) / 2) + (cleanOffsetY * maxY)
    )
    return NSRect(origin: origin, size: croppedSize)
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

private func parseDictionaryEntries(_ text: String) -> [DictionaryReplacement] {
  text
    .components(separatedBy: .newlines)
    .compactMap { line -> DictionaryReplacement? in
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }

      let separators = ["=>", "="]
      for separator in separators {
        if let range = trimmed.range(of: separator) {
          let trigger = trimmed[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
          let replacement = trimmed[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
          if !trigger.isEmpty, !replacement.isEmpty {
            return DictionaryReplacement(trigger: trigger, replacement: replacement)
          }
        }
      }
      return nil
    }
}

private func serializeDictionaryEntries(_ entries: [DictionaryReplacement]) -> String {
  entries
    .map {
      DictionaryReplacement(
        trigger: $0.trigger.trimmingCharacters(in: .whitespacesAndNewlines),
        replacement: $0.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
      )
    }
    .filter { !$0.trigger.isEmpty && !$0.replacement.isEmpty }
    .map { "\($0.trigger) = \($0.replacement)" }
    .joined(separator: "\n")
}

private func intValue(_ value: Any?) -> Int {
  if let int = value as? Int { return int }
  if let double = value as? Double { return Int(double) }
  if let number = value as? NSNumber { return number.intValue }
  return 0
}

private func localTodayStartISO() -> String {
  let start = Calendar.current.startOfDay(for: Date())
  return ISO8601DateFormatter().string(from: start)
}

private func byteString(_ bytes: Int) -> String {
  if bytes < 1024 { return "\(bytes) B" }
  let kb = Double(bytes) / 1024
  if kb < 1024 { return String(format: "%.1f KB", kb) }
  return String(format: "%.1f MB", kb / 1024)
}
