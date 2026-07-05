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
  // Newly picked image file, held until the crop is confirmed so Cancel
  // doesn't clobber the stored original.
  private var pendingOriginalImageURL: URL?
  private var isStartingRecording = false
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
  private var keywordsPane: NSView?
  private var keywordsTextView: NSTextView?
  private var keywordsStatusLabel: NSTextField?
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
  private var realtimeSession: RealtimeSession?
  private var transcriptionModeControl: NSSegmentedControl?
  private var tabletBlurView: NSVisualEffectView?
  private var modePillButton: NSButton?
  // Current height of the live sheet; grows (never shrinks) within a session.
  private var liveSheetHeight: CGFloat = TabletShape.rectangle.expandedPanelSize.height
  private var tabletImageOpacitySlider: NSSlider?
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
      tabletImageOpacitySlider = nil
      tabletPreviewHost = nil
      tabletPreviewView = nil
      shortcutButton = nil
      transcriptionModeControl = nil
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
      keywordsPane = nil
      keywordsTextView = nil
      keywordsStatusLabel = nil
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
    tabletPanel.backgroundColor = .clear
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

    // Liquid glass base: real behind-window blur clipped to the tablet shape
    // (via maskImage — layer cornerRadius breaks NSVisualEffectView blur).
    let blur = NSVisualEffectView(frame: contentRect)
    blur.material = .hudWindow
    blur.blendingMode = .behindWindow
    blur.state = .active
    blur.appearance = NSAppearance(named: .darkAqua)
    content.addSubview(blur)
    tabletBlurView = blur

    tabletView = TabletView(frame: .zero)
    applyTabletAppearance()
    content.addSubview(tabletView)

    statusLabel = NSTextField(labelWithString: "Ready")
    statusLabel.textColor = NSColor.white.withAlphaComponent(0.72)
    statusLabel.font = NSFont.systemFont(ofSize: 8, weight: .medium)
    statusLabel.lineBreakMode = .byTruncatingTail
    statusLabel.maximumNumberOfLines = 1
    content.addSubview(statusLabel)

    let pill = NSButton(title: "", target: self, action: #selector(toggleTranscriptionModeFromTablet))
    pill.isBordered = false
    pill.wantsLayer = true
    pill.layer?.cornerRadius = 7
    pill.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
    pill.toolTip = "Switch between live transcription and transcribe-on-stop"
    content.addSubview(pill)
    modePillButton = pill

    tabletPanel.contentView = content
    applyTabletAppearance()
    refreshModePill()
  }

  // Mode pill (bottom-right of the glass sheet): tap to flip between live
  // streaming and transcribe-on-stop without opening Settings. Applies to the
  // next dictation if one is already running.
  @objc private func toggleTranscriptionModeFromTablet() {
    let next: TranscriptionMode = Preferences.shared.transcriptionMode == .realtime ? .batch : .realtime
    Preferences.shared.transcriptionMode = next
    refreshModePill()
    transcriptionModeControl?.selectedSegment = next == .realtime ? 1 : 0
    if !isRecording {
      setReadyStatus()
    }
  }

  private func refreshModePill() {
    let live = Preferences.shared.transcriptionMode == .realtime
    let title = NSAttributedString(
      string: live ? "LIVE" : "ON STOP",
      attributes: [
        .font: NSFont.systemFont(ofSize: 8, weight: .bold),
        .foregroundColor: NSColor.white.withAlphaComponent(live ? 0.95 : 0.6),
      ]
    )
    modePillButton?.attributedTitle = title
    modePillButton?.layer?.backgroundColor = live
      ? NSColor(calibratedRed: 0.18, green: 0.92, blue: 1, alpha: 0.22).cgColor
      : NSColor.white.withAlphaComponent(0.12).cgColor
  }

  @objc private func showTabletFromMenu() {
    showTabletPanel(positionAtBottom: false)
  }

  private func showTabletPanel(positionAtBottom: Bool) {
    let wasVisible = tabletPanel.isVisible
    if positionAtBottom || !wasVisible {
      placeTabletAtBottom()
    }
    tabletPanel.orderFrontRegardless()
    if !wasVisible {
      popInTablet()
    }
  }

  // iOS-sheet style entrance: springy scale-up plus a quick fade.
  private func popInTablet() {
    guard let content = tabletPanel.contentView else { return }
    content.wantsLayer = true
    guard let layer = content.layer else { return }

    layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    layer.position = CGPoint(x: content.bounds.midX, y: content.bounds.midY)

    let spring = CASpringAnimation(keyPath: "transform.scale")
    spring.fromValue = 0.82
    spring.toValue = 1
    spring.damping = 16
    spring.stiffness = 260
    spring.initialVelocity = 4
    spring.duration = spring.settlingDuration
    layer.add(spring, forKey: "pop-in")

    tabletPanel.alphaValue = 0
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.16
      tabletPanel.animator().alphaValue = 1
    }
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
    // isStartingRecording covers the async mic-permission gap so a rapid
    // double shortcut press can't spin up two sessions.
    guard !isRecording, !isStartingRecording else { return }
    isStartingRecording = true

    pasteTargetApp = currentExternalApp() ?? lastExternalApp
    showTabletPanel(positionAtBottom: true)
    refreshAccessibilityStatus()
    requestMicrophoneAccess { [weak self] granted in
      guard let self else { return }
      DispatchQueue.main.async {
        defer { self.isStartingRecording = false }
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
    if Preferences.shared.transcriptionMode == .realtime {
      beginRealtimeSession()
      return
    }
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

  private func beginRealtimeSession() {
    let session = RealtimeSession()
    session.onLevel = { [weak self] level in
      guard let self else { return }
      self.smoothedAudioLevel = (self.smoothedAudioLevel * 0.68) + (level * 0.32)
      self.tabletView.audioLevel = self.smoothedAudioLevel
    }
    session.onInterim = { [weak self] _ in
      guard let self, let session = self.realtimeSession else { return }
      self.tabletView.liveText = session.liveDisplayText
      self.growLiveSheetIfNeeded()
    }
    session.onFinal = { [weak self] _ in
      guard let self, let session = self.realtimeSession else { return }
      self.tabletView.liveText = session.liveDisplayText
      self.growLiveSheetIfNeeded()
    }
    session.onError = { [weak self] message in
      self?.setStatus(message)
    }

    do {
      try session.start(url: realtimeURL(), apiKey: Preferences.shared.apiKey)
    } catch {
      // Don't leak the already-opened socket or the temp WAV.
      session.cancel()
      if let url = session.recordingURL {
        try? FileManager.default.removeItem(at: url)
      }
      setStatus("Live session failed: \(error.localizedDescription)")
      hideTablet(after: 1.6)
      return
    }

    realtimeSession = session
    isRecording = true
    smoothedAudioLevel = 0
    liveSheetHeight = TabletShape.rectangle.expandedPanelSize.height
    tabletView.isRecording = true
    tabletView.audioLevel = 0
    tabletView.liveText = ""
    applyTabletAppearance()
    placeTabletAtBottom() // recenter: the sheet expands for live text
    registerEscapeHotKey()
    installEscapeMonitors()
    startGlowAnimation()
    playStartSound()
    setStatus("Listening (live)")
  }

  private func stopRealtimeSession() {
    guard let session = realtimeSession else { return }
    realtimeSession = nil
    isRecording = false
    tabletView.isRecording = false
    tabletView.audioLevel = 0
    applyTabletAppearance()
    placeTabletAtBottom() // shrink back from the expanded live sheet
    unregisterEscapeHotKey()
    removeEscapeMonitors()
    stopGlowAnimation()
    playStopSound()
    setStatus("Finishing")

    Task { [weak self] in
      let transcript = await session.finalize()
      await self?.processRealtimeResult(transcript: transcript, fileURL: session.recordingURL)
    }
  }

  private func processRealtimeResult(transcript: String, fileURL: URL?) async {
    defer {
      if let fileURL {
        try? FileManager.default.removeItem(at: fileURL)
      }
    }
    DispatchQueue.main.async {
      self.tabletView.liveText = ""
    }

    let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      // The connection may have died mid-session — keep the side-recorded
      // WAV so the user can retry from History instead of losing the take.
      if let fileURL, let savedURL = try? TranscriptStore.shared.storeAudio(fileURL) {
        insertHistoryEntry(
          TranscriptEntry(
            id: UUID().uuidString,
            createdAt: Date(),
            rawText: "",
            cleanedText: "",
            audioPath: savedURL.path,
            status: "Saved for retry"
          )
        )
        setStatus("No transcript. Audio saved for retry.")
      } else {
        setStatus("No speech detected.")
      }
      hideTablet(after: 1.4)
      return
    }

    let finalText: String
    if Preferences.shared.polishWithGPT {
      setStatus("Cleaning")
      do {
        finalText = try await clean(transcript: trimmed)
      } catch {
        finalText = trimmed
        setStatus("Cleanup unavailable; pasting raw.")
      }
    } else {
      finalText = trimmed
    }

    let savedURL = fileURL.flatMap { try? TranscriptStore.shared.storeAudio($0) }
    insertHistoryEntry(
      TranscriptEntry(
        id: UUID().uuidString,
        createdAt: Date(),
        rawText: trimmed,
        cleanedText: finalText,
        audioPath: savedURL?.path,
        status: "Complete"
      )
    )
    paste(finalText)
  }

  private func cancelRealtimeForRetry() {
    guard let session = realtimeSession else { return }
    realtimeSession = nil
    isRecording = false
    tabletView.isRecording = false
    tabletView.audioLevel = 0
    tabletView.liveText = ""
    applyTabletAppearance()
    placeTabletAtBottom()
    unregisterEscapeHotKey()
    removeEscapeMonitors()
    stopGlowAnimation()
    playStopSound()
    session.cancel()

    if let fileURL = session.recordingURL,
      let savedURL = try? TranscriptStore.shared.storeAudio(fileURL)
    {
      insertHistoryEntry(
        TranscriptEntry(
          id: UUID().uuidString,
          createdAt: Date(),
          rawText: "",
          cleanedText: "",
          audioPath: savedURL.path,
          status: "Saved for retry"
        )
      )
      setStatus("Saved for retry")
      try? FileManager.default.removeItem(at: fileURL)
    } else {
      setStatus("Cancelled")
    }
    hideTablet(after: 1.2)
  }

  private func stopRecording() {
    guard isRecording else { return }
    if realtimeSession != nil {
      stopRealtimeSession()
      return
    }
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
    if realtimeSession != nil {
      cancelRealtimeForRetry()
      return
    }
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

      let finalText: String
      if Preferences.shared.polishWithGPT {
        setStatus("Cleaning")
        do {
          finalText = try await clean(transcript: transcript)
        } catch {
          finalText = transcript
          setStatus("Cleanup unavailable; pasting raw.")
        }
      } else {
        finalText = transcript
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
    var request = URLRequest(url: transcribeURL())
    request.httpMethod = "POST"
    // Realtime sessions store WAV retry audio; batch recordings are m4a.
    let contentType = fileURL.pathExtension.lowercased() == "wav" ? "audio/wav" : "audio/m4a"
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    addAPIKeyHeader(to: &request)

    let data = try Data(contentsOf: fileURL)
    let (responseData, response) = try await URLSession.shared.upload(for: request, from: data)
    let json = try decodeAPIResponse(data: responseData, response: response, label: "transcribe")
    return json["transcript"] as? String ?? ""
  }

  // Builds /transcribe with Deepgram accuracy params:
  //  - replace=find:replace  from the Dictionary tab (Deepgram requires the
  //    Find side lowercase; the Replace side keeps its casing).
  //  - keyterm=term          from the Keywords tab (boosts recognition).
  // Both are applied at the Deepgram layer, so they work even when the GPT
  // polish step is off.
  private func transcribeURL() -> URL {
    withAccuracyParams(apiURL(path: "/transcribe"))
  }

  // Realtime proxy endpoint: same origin as the REST API but ws(s) scheme.
  // Dictionary + keyword params ride along so live sessions get the same
  // Deepgram accuracy treatment as batch /transcribe.
  private func realtimeURL() -> URL {
    let base = withAccuracyParams(apiURL(path: "/realtime"))
    guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
      return base
    }
    components.scheme = components.scheme == "http" ? "ws" : "wss"
    return components.url ?? base
  }

  private func withAccuracyParams(_ base: URL) -> URL {
    guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
      return base
    }
    var items: [URLQueryItem] = []

    for entry in Preferences.shared.dictionaryEntries {
      let find = entry.trigger.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let replacement = entry.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !find.isEmpty, !replacement.isEmpty else { continue }
      items.append(URLQueryItem(name: "replace", value: "\(find):\(replacement)"))
    }

    for term in Preferences.shared.keywords.prefix(100) {
      items.append(URLQueryItem(name: "keyterm", value: term))
    }

    guard !items.isEmpty else { return base }
    components.queryItems = (components.queryItems ?? []) + items
    // URLComponents leaves a literal "+" in query values, but the server
    // reparses with WHATWG URLSearchParams, which decodes "+" as a space —
    // so encode it explicitly to keep terms like "C++" intact.
    components.percentEncodedQuery = components.percentEncodedQuery?
      .replacingOccurrences(of: "+", with: "%2B")
    return components.url ?? base
  }

  private func clean(transcript: String) async throws -> String {
    var request = URLRequest(url: apiURL(path: "/clean"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    addAPIKeyHeader(to: &request)

    // Dictionary find/replace now runs at the Deepgram layer (see
    // transcribeURL), so /clean only does GPT polish here.
    let body: [String: Any] = ["text": transcript]

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

    let tabs = NSSegmentedControl(labels: ["Settings", "Dictionary", "Keywords", "Usage", "History"], trackingMode: .selectOne, target: self, action: #selector(switchMainPane))
    tabs.frame = NSRect(x: 24, y: height - 48, width: 470, height: 28)
    tabs.selectedSegment = 0
    content.addSubview(tabs)
    tabControl = tabs

    let paneFrame = NSRect(x: 0, y: 0, width: width, height: height - 64)
    let settingsPane = buildSettingsPane(frame: paneFrame)
    let dictionaryPane = buildDictionaryPane(frame: paneFrame)
    let keywordsPane = buildKeywordsPane(frame: paneFrame)
    let usagePane = buildUsagePane(frame: paneFrame)
    let historyPane = buildHistoryPane(frame: paneFrame)
    dictionaryPane.isHidden = true
    keywordsPane.isHidden = true
    usagePane.isHidden = true
    historyPane.isHidden = true

    content.addSubview(settingsPane)
    content.addSubview(dictionaryPane)
    content.addSubview(keywordsPane)
    content.addSubview(usagePane)
    content.addSubview(historyPane)
    self.settingsPane = settingsPane
    self.dictionaryPane = dictionaryPane
    self.keywordsPane = keywordsPane
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

    let adjustImageButton = NSButton(title: "Adjust Image...", target: self, action: #selector(adjustTabletImage))
    adjustImageButton.frame = NSRect(x: 304, y: 424, width: 124, height: 30)
    adjustImageButton.bezelStyle = .rounded
    adjustImageButton.toolTip = "Reposition or re-zoom the current image inside the tablet"
    content.addSubview(adjustImageButton)

    let clearImageButton = NSButton(title: "Clear Image", target: self, action: #selector(clearTabletImage))
    clearImageButton.frame = NSRect(x: 440, y: 424, width: 124, height: 30)
    clearImageButton.bezelStyle = .rounded
    content.addSubview(clearImageButton)

    let imageStatus = NSTextField(labelWithString: tabletImageStatusText())
    imageStatus.frame = NSRect(x: 168, y: 400, width: 396, height: 16)
    imageStatus.font = NSFont.systemFont(ofSize: 11)
    imageStatus.textColor = NSColor.secondaryLabelColor
    imageStatus.lineBreakMode = .byTruncatingMiddle
    content.addSubview(imageStatus)
    tabletImageStatusLabel = imageStatus

    addLabel("Image opacity", y: 372)
    let opacitySlider = NSSlider(
      value: Preferences.shared.tabletImageOpacity,
      minValue: 0.1,
      maxValue: 1,
      target: self,
      action: #selector(tabletAppearanceControlChanged)
    )
    opacitySlider.frame = NSRect(x: 168, y: 368, width: 220, height: 24)
    opacitySlider.isContinuous = true
    opacitySlider.toolTip = "How strongly the image shows through the glass"
    content.addSubview(opacitySlider)
    tabletImageOpacitySlider = opacitySlider

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
    shapeLabel.frame = NSRect(x: 32, y: 330, width: 120, height: 18)
    content.addSubview(shapeLabel)

    let shapeControl = NSSegmentedControl(labels: ["Rectangle", "Circle"], trackingMode: .selectOne, target: self, action: #selector(tabletAppearanceControlChanged))
    shapeControl.frame = NSRect(x: 168, y: 324, width: 220, height: 28)
    shapeControl.selectedSegment = Preferences.shared.tabletShape == .circle ? 1 : 0
    content.addSubview(shapeControl)
    tabletShapeControl = shapeControl

    let borderLabel = NSTextField(labelWithString: "Border color")
    borderLabel.frame = NSRect(x: 32, y: 284, width: 120, height: 18)
    content.addSubview(borderLabel)

    let colorWell = NSColorWell(frame: NSRect(x: 168, y: 276, width: 58, height: 32))
    colorWell.color = Preferences.shared.tabletBorderColor
    colorWell.target = self
    colorWell.action = #selector(tabletAppearanceControlChanged)
    content.addSubview(colorWell)
    tabletBorderColorWell = colorWell

    let shortcutLabel = NSTextField(labelWithString: "Shortcut")
    shortcutLabel.frame = NSRect(x: 32, y: 246, width: 120, height: 18)
    content.addSubview(shortcutLabel)

    let shortcutButton = NSButton(title: Preferences.shared.shortcut.title, target: self, action: #selector(beginShortcutCapture))
    shortcutButton.frame = NSRect(x: 168, y: 240, width: 396, height: 30)
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

    let modeControl = NSSegmentedControl(
      labels: ["Transcribe on stop", "Live transcription"],
      trackingMode: .selectOne,
      target: self,
      action: #selector(transcriptionModeChanged)
    )
    modeControl.frame = NSRect(x: 32, y: 22, width: 300, height: 26)
    modeControl.selectedSegment = Preferences.shared.transcriptionMode == .realtime ? 1 : 0
    modeControl.toolTip =
      "On stop: record, then transcribe when you end dictation. Live: words stream onto the tablet as you speak."
    content.addSubview(modeControl)
    transcriptionModeControl = modeControl

    let polishCheckbox = NSButton(
      checkboxWithTitle: "Polish transcript with GPT (slower, cleaner)",
      target: self,
      action: #selector(togglePolishWithGPT(_:))
    )
    polishCheckbox.frame = NSRect(x: 32, y: 58, width: 320, height: 20)
    polishCheckbox.state = Preferences.shared.polishWithGPT ? .on : .off
    polishCheckbox.toolTip =
      "Off: paste Deepgram output directly (faster). On: pipe through OpenAI /clean to strip verbal tics."
    content.addSubview(polishCheckbox)

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

  @objc private func togglePolishWithGPT(_ sender: NSButton) {
    Preferences.shared.polishWithGPT = (sender.state == .on)
  }

  @objc private func transcriptionModeChanged() {
    let mode: TranscriptionMode = transcriptionModeControl?.selectedSegment == 1 ? .realtime : .batch
    Preferences.shared.transcriptionMode = mode
    setStatus(mode == .realtime ? "Live transcription on" : "Transcribe on stop")
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

  private func buildKeywordsPane(frame: NSRect) -> NSView {
    let content = NSView(frame: frame)

    let title = NSTextField(labelWithString: "Keywords")
    title.frame = NSRect(x: 32, y: frame.height - 92, width: 200, height: 22)
    title.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
    content.addSubview(title)

    let blurb = NSTextField(wrappingLabelWithString:
      "Boost recognition of names, product terms, or jargon — e.g. gmail, Jerel, Hushly. "
      + "Deepgram pays extra attention to these so they get transcribed correctly. "
      + "Up to 100, separated by commas or new lines.")
    blurb.frame = NSRect(x: 32, y: frame.height - 156, width: 532, height: 52)
    blurb.textColor = NSColor.secondaryLabelColor
    blurb.font = NSFont.systemFont(ofSize: 12)
    content.addSubview(blurb)

    let scroll = NSScrollView(frame: NSRect(x: 32, y: 86, width: 532, height: frame.height - 270))
    scroll.borderType = .bezelBorder
    scroll.hasVerticalScroller = true
    let textView = NSTextView(frame: scroll.bounds)
    textView.minSize = NSSize(width: 0, height: 0)
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.textContainerInset = NSSize(width: 6, height: 8)
    textView.font = NSFont.systemFont(ofSize: 13)
    textView.isRichText = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.string = Preferences.shared.keywordsText
    scroll.documentView = textView
    content.addSubview(scroll)
    keywordsTextView = textView

    let example = NSTextField(labelWithString: "Example: gmail, Jerel, Hushly, Deepgram")
    example.frame = NSRect(x: 32, y: 58, width: 380, height: 18)
    example.textColor = NSColor.secondaryLabelColor
    example.font = NSFont.systemFont(ofSize: 11)
    content.addSubview(example)

    let status = NSTextField(labelWithString: keywordsStatusText())
    status.frame = NSRect(x: 32, y: 28, width: 250, height: 18)
    status.textColor = NSColor.secondaryLabelColor
    status.font = NSFont.systemFont(ofSize: 11)
    status.lineBreakMode = .byTruncatingTail
    content.addSubview(status)
    keywordsStatusLabel = status

    let saveButton = NSButton(title: "Save Keywords", target: self, action: #selector(saveKeywords))
    saveButton.frame = NSRect(x: 420, y: 20, width: 144, height: 32)
    saveButton.bezelStyle = .rounded
    content.addSubview(saveButton)

    return content
  }

  private func keywordsStatusText() -> String {
    let count = Preferences.shared.keywords.count
    return count == 1 ? "1 keyword saved" : "\(count) keywords saved"
  }

  @objc private func saveKeywords() {
    Preferences.shared.keywordsText = keywordsTextView?.string ?? ""
    keywordsStatusLabel?.stringValue = keywordsStatusText()
    setStatus("Keywords saved")
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
    keywordsPane?.isHidden = selected != 2
    usagePane?.isHidden = selected != 3
    historyPane?.isHidden = selected != 4
    if selected == 3 {
      refreshUsage()
    } else if selected == 4 {
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
    tabletImageOpacitySlider?.doubleValue = Preferences.shared.tabletImageOpacity
    apiBaseField?.stringValue = Preferences.shared.apiBase
    apiKeyField?.stringValue = Preferences.shared.apiKey
    dictionaryStatusLabel?.stringValue = dictionaryStatusText()
    usageStatusLabel?.stringValue = usageStatusText()
    shortcutButton?.title = Preferences.shared.shortcut.title
    transcriptionModeControl?.selectedSegment = Preferences.shared.transcriptionMode == .realtime ? 1 : 0
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
    view?.imageOpacity = CGFloat(Preferences.shared.tabletImageOpacity)
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

  private func layoutTabletPanel(animated: Bool = false) {
    guard let tabletPanel, let content = tabletPanel.contentView else { return }
    let shape = Preferences.shared.tabletShape
    let expanded = isRecording && realtimeSession != nil && shape == .rectangle
    let size = expanded
      ? NSSize(width: shape.expandedPanelSize.width, height: liveSheetHeight)
      : shape.panelSize
    let origin = tabletPanel.frame.origin
    content.frame = NSRect(origin: .zero, size: size)

    let radius: CGFloat = shape == .circle ? size.width / 2 : 18
    tabletBlurView?.frame = content.bounds
    tabletBlurView?.maskImage = Self.glassMask(size: size, radius: radius)

    tabletView?.frame = shape.tabletFrame(panelSize: size)
    tabletView?.isExpanded = expanded

    statusLabel?.isHidden = shape == .circle
    statusLabel?.frame = NSRect(x: 14, y: 4, width: size.width - 92, height: 10)
    modePillButton?.isHidden = shape == .circle
    modePillButton?.frame = NSRect(x: size.width - 66, y: 3, width: 54, height: 14)

    if animated {
      // Origin (bottom-left) stays put, so added height rises upward.
      tabletPanel.setFrame(NSRect(origin: origin, size: size), display: true, animate: true)
    } else {
      tabletPanel.setContentSize(size)
      tabletPanel.setFrameOrigin(origin)
    }
  }

  // Called on each transcript update: measure the wrapped live text and let
  // the sheet rise (grow-only) to fit, up to liveMaxHeight. Once capped,
  // drawLiveTranscript trims from the head instead.
  private func growLiveSheetIfNeeded() {
    guard realtimeSession != nil, Preferences.shared.tabletShape == .rectangle else { return }
    let panelWidth = TabletShape.rectangle.expandedPanelSize.width
    // panel → tablet frame (-16) → text insets (-32); height adds back the
    // text's top/bottom insets (36) and the tablet frame's chrome (26).
    let textHeight = TabletView.liveTextHeight(tabletView.liveText, width: panelWidth - 48, expanded: true)
    let needed = min(max(TabletShape.rectangle.expandedPanelSize.height, textHeight + 62), TabletShape.liveMaxHeight)
    guard needed > liveSheetHeight else { return }
    liveSheetHeight = needed
    layoutTabletPanel(animated: true)
  }

  // Resizable rounded-rect (or circle) mask that clips the blur to the glass
  // sheet without killing NSVisualEffectView's blur pass.
  private static func glassMask(size: NSSize, radius: CGFloat) -> NSImage {
    let image = NSImage(size: size, flipped: false) { rect in
      NSColor.black.setFill()
      NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
      return true
    }
    image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
    image.resizingMode = .stretch
    return image
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
    lines.append("  Words transcribed: \(intValue(today["wordCount"]))")
    lines.append("  Talk time: \(formatTalkTime(today["audioDurationSeconds"]))")
    lines.append("  Time saved vs typing: \(timeSavedString(today["wordCount"]))")
    lines.append("  Transcriptions: \(intValue(today["transcriptions"]))")
    lines.append("  Cleanups: \(intValue(today["cleanups"]))")
    lines.append("  Errors: \(intValue(today["errors"]))")
    lines.append("  Audio uploaded: \(byteString(intValue(today["audioBytes"])))")
    lines.append("")
    lines.append("Last 30 days")
    lines.append("  Words transcribed: \(intValue(month["wordCount"]))")
    lines.append("  Talk time: \(formatTalkTime(month["audioDurationSeconds"]))")
    lines.append("  Time saved vs typing: \(timeSavedString(month["wordCount"]))")
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
      if Preferences.shared.polishWithGPT {
        do {
          finalText = try await clean(transcript: transcript)
        } catch {
          finalText = transcript
        }
      } else {
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
    Preferences.shared.tabletImageOpacity = tabletImageOpacitySlider?.doubleValue ?? Preferences.shared.tabletImageOpacity
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
      // Held until Use Image — Cancel must not clobber the stored original.
      self.pendingOriginalImageURL = url
      self.showCropWindow(for: image, shape: self.selectedTabletShape())
    }
  }

  // Reopens the crop sheet on the stored original with the last-used zoom and
  // offsets, so the image can be repositioned without re-importing.
  @objc private func adjustTabletImage() {
    let path = Preferences.shared.tabletOriginalImagePath
    guard !path.isEmpty, let image = NSImage(contentsOfFile: path) else {
      setStatus("Choose an image first")
      return
    }
    showCropWindow(
      for: image,
      shape: selectedTabletShape(),
      zoom: Preferences.shared.tabletImageZoom,
      offsetX: Preferences.shared.tabletImageCropX,
      offsetY: Preferences.shared.tabletImageCropY
    )
  }

  @objc private func clearTabletImage() {
    Preferences.shared.tabletImagePath = ""
    Preferences.shared.tabletOriginalImagePath = ""
    Preferences.shared.tabletImageZoom = 1
    Preferences.shared.tabletImageCropX = 0
    Preferences.shared.tabletImageCropY = 0
    try? TabletAssetStore.shared.clearBackground()
    applyTabletAppearance()
    refreshSettingsFields()
    setStatus("Tablet image cleared")
  }

  private func showCropWindow(
    for image: NSImage,
    shape: TabletShape,
    zoom: Double = 1,
    offsetX: Double = 0,
    offsetY: Double = 0
  ) {
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

    cropZoomSlider = addCropSlider(to: content, title: "Zoom", y: 112, min: 1, max: 3, value: zoom)
    cropXSlider = addCropSlider(to: content, title: "Horizontal", y: 78, min: -1, max: 1, value: offsetX)
    cropYSlider = addCropSlider(to: content, title: "Vertical", y: 44, min: -1, max: 1, value: offsetY)
    preview.zoom = CGFloat(zoom)
    preview.offsetX = CGFloat(offsetX)
    preview.offsetY = CGFloat(offsetY)

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
      Preferences.shared.tabletImageZoom = cropZoomSlider?.doubleValue ?? 1
      Preferences.shared.tabletImageCropX = cropXSlider?.doubleValue ?? 0
      Preferences.shared.tabletImageCropY = cropYSlider?.doubleValue ?? 0
      if let pendingURL = pendingOriginalImageURL,
        let originalURL = try? TabletAssetStore.shared.storeOriginal(from: pendingURL)
      {
        Preferences.shared.tabletOriginalImagePath = originalURL.path
      }
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
    pendingOriginalImageURL = nil
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
      // Realtime sessions push levels via RealtimeSession.onLevel; the timer
      // then only drives the waveform's phase animation.
      if let recorder = self.recorder {
        recorder.updateMeters()
        let averagePower = recorder.averagePower(forChannel: 0)
        let normalized = max(0, min(1, CGFloat((averagePower + 50) / 50)))
        self.smoothedAudioLevel = (self.smoothedAudioLevel * 0.68) + (normalized * 0.32)
        self.tabletView.audioLevel = self.smoothedAudioLevel
      }
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
      NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.18
        self.tabletPanel.animator().alphaValue = 0
      }, completionHandler: {
        guard !self.isRecording else {
          self.tabletPanel.alphaValue = 1
          return
        }
        self.tabletPanel.orderOut(nil)
        self.tabletPanel.alphaValue = 1
      })
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

enum TranscriptionMode: String {
  case batch
  case realtime
}

enum TabletShape: String {
  case rectangle
  case circle

  var panelSize: NSSize {
    switch self {
    case .rectangle:
      return NSSize(width: 264, height: 72)
    case .circle:
      return NSSize(width: 84, height: 84)
    }
  }

  // Starting size of the live sheet; it rises from here as text wraps onto
  // more lines (AppDelegate.growLiveSheetIfNeeded, capped at liveMaxHeight).
  // The circle keeps its size — it has no live-text region.
  var expandedPanelSize: NSSize {
    switch self {
    case .rectangle:
      return NSSize(width: 384, height: 96)
    case .circle:
      return panelSize
    }
  }

  static let liveMaxHeight: CGFloat = 264

  func tabletFrame(panelSize size: NSSize) -> NSRect {
    switch self {
    case .rectangle:
      return NSRect(x: 8, y: 18, width: size.width - 16, height: size.height - 26)
    case .circle:
      return NSRect(x: 11, y: 11, width: size.width - 22, height: size.height - 22)
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

  // Opacity of the custom image layered inside the glass (user slider).
  var imageOpacity: CGFloat = 0.55 {
    didSet { needsDisplay = true }
  }

  // True while a realtime session has grown the sheet for streaming text.
  var isExpanded = false {
    didSet { needsDisplay = true }
  }

  var statusText = "Ready" {
    didSet { needsDisplay = true }
  }

  // Streaming transcript shown while a realtime session is active. When
  // non-empty it replaces displayText so the user watches words land live.
  var liveText = "" {
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

  override func draw(_ dirtyRect: NSRect) {
    NSColor.clear.setFill()
    dirtyRect.fill()

    // The blur lives in the panel's NSVisualEffectView behind this view;
    // here we composite the glass tint, the user's translucent image, the
    // rim light, and the content.
    let clipPath = shapePath(in: bounds.insetBy(dx: 1, dy: 1))
    NSGraphicsContext.saveGraphicsState()
    clipPath.addClip()

    NSColor(calibratedWhite: 0, alpha: 0.22).setFill()
    bounds.fill()

    if let customBackgroundImage {
      let fraction = min(1, max(0.05, imageOpacity + (isRecording ? 0.08 : 0)))
      // Aspect-fill: crop the source to the view's aspect instead of
      // stretching — the live sheet's proportions differ from the baked crop.
      let source = TabletAssetStore.cropRect(
        for: customBackgroundImage.size,
        targetAspect: bounds.width / max(1, bounds.height),
        zoom: 1,
        offsetX: 0,
        offsetY: 0
      )
      customBackgroundImage.draw(in: bounds, from: source, operation: .sourceOver, fraction: fraction)
    }

    // Top sheen: soft vertical highlight that sells the glass curvature.
    let sheen = NSGradient(
      starting: NSColor(calibratedWhite: 1, alpha: 0.16),
      ending: NSColor(calibratedWhite: 1, alpha: 0)
    )
    let sheenRect = NSRect(x: bounds.minX, y: bounds.midY, width: bounds.width, height: bounds.height / 2)
    sheen?.draw(in: sheenRect, angle: -90)

    NSGraphicsContext.restoreGraphicsState()

    drawRimLight()
    drawGrabHandle()
    if showsDisplayText || isRecording {
      drawDisplayText()
    }
    drawWaveform()
  }

  private func drawRimLight() {
    let stroke = shapePath(in: bounds.insetBy(dx: 1.5, dy: 1.5))
    if isRecording {
      NSGraphicsContext.saveGraphicsState()
      let glow = NSShadow()
      glow.shadowColor = borderColor.withAlphaComponent(0.7)
      glow.shadowBlurRadius = 6 + (audioLevel * 6)
      glow.shadowOffset = .zero
      glow.set()
      borderColor.withAlphaComponent(0.85).setStroke()
      stroke.lineWidth = 1.5
      stroke.stroke()
      NSGraphicsContext.restoreGraphicsState()
    } else {
      NSColor(calibratedWhite: 1, alpha: 0.28).setStroke()
      stroke.lineWidth = 1
      stroke.stroke()
    }
  }

  private func drawGrabHandle() {
    guard shape == .rectangle else { return }
    let handle = NSRect(x: bounds.midX - 18, y: bounds.maxY - 9, width: 36, height: 4.5)
    NSColor(calibratedWhite: 1, alpha: 0.3).setFill()
    NSBezierPath(roundedRect: handle, xRadius: 2.25, yRadius: 2.25).fill()
  }

  private func drawDisplayText() {
    let live = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
    if isRecording && !live.isEmpty {
      drawLiveTranscript(live)
      return
    }

    let cleanText = displayText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanText.isEmpty, showsDisplayText else { return }

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byTruncatingTail

    let shadow = NSShadow()
    shadow.shadowColor = borderColor.withAlphaComponent(0.88)
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

  private static func liveFont(expanded: Bool) -> NSFont {
    NSFont.systemFont(ofSize: expanded ? 15 : 12, weight: .medium)
  }

  private static func liveAttributes(expanded: Bool) -> [NSAttributedString.Key: Any] {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    paragraph.lineBreakMode = .byWordWrapping
    return [
      .font: liveFont(expanded: expanded),
      .foregroundColor: NSColor.white.withAlphaComponent(0.96),
      .paragraphStyle: paragraph,
    ]
  }

  // Wrapped height of the live transcript at a given width — used by the
  // AppDelegate to decide how far the sheet should rise.
  static func liveTextHeight(_ text: String, width: CGFloat, expanded: Bool) -> CGFloat {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty, width > 20 else { return 0 }
    return ceil(
      (clean as NSString).boundingRect(
        with: NSSize(width: width, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin],
        attributes: liveAttributes(expanded: expanded)
      ).height
    )
  }

  // Streaming transcript: left-aligned and anchored to the top so words read
  // naturally left→right, top→down as they arrive. When the text outgrows
  // the area (sheet already at max height) we binary-search the shortest
  // suffix that still fits (suffixes are monotonic in height), prefixed with
  // an ellipsis.
  private func drawLiveTranscript(_ text: String) {
    let attrs = Self.liveAttributes(expanded: isExpanded)

    // Leave room for the grab handle above and the waveform below.
    let topInset: CGFloat = shape == .rectangle ? 14 : 18
    let bottomInset: CGFloat = 22
    let area = NSRect(
      x: bounds.minX + 16,
      y: bounds.minY + bottomInset,
      width: bounds.width - 32,
      height: max(14, bounds.height - bottomInset - topInset)
    )
    guard area.width > 20 else { return }

    let words = text.split(separator: " ").map(String.init)
    func rendered(from start: Int) -> String {
      let suffix = words[start...].joined(separator: " ")
      return start == 0 ? suffix : "… " + suffix
    }
    func height(of string: String) -> CGFloat {
      (string as NSString).boundingRect(
        with: NSSize(width: area.width, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin],
        attributes: attrs
      ).height
    }

    var display = rendered(from: 0)
    if height(of: display) > area.height, words.count > 1 {
      var low = 1
      var high = words.count - 1
      while low < high {
        let mid = (low + high) / 2
        if height(of: rendered(from: mid)) <= area.height {
          high = mid
        } else {
          low = mid + 1
        }
      }
      display = rendered(from: low)
    }

    let measured = min(height(of: display), area.height)
    // Top-anchored (non-flipped coords: top is maxY) so text flows downward.
    let drawRect = NSRect(
      x: area.minX,
      y: area.maxY - measured,
      width: area.width,
      height: measured
    )
    (display as NSString).draw(
      with: drawRect,
      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
      attributes: attrs
    )
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
    let barCount = isExpanded ? 22 : 12
    let totalWidth: CGFloat = shape == .circle ? 38 : (isExpanded ? 150 : 84)
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
      borderColor.withAlphaComponent(isRecording ? 0.95 : 0.34).setFill()
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
  private let keywordsTextKey = "keywordsText"
  private let polishWithGPTKey = "polishWithGPT"
  private let transcriptionModeKey = "transcriptionMode"
  private let tabletImageOpacityKey = "tabletImageOpacity"
  private let tabletOriginalImagePathKey = "tabletOriginalImagePath"
  private let tabletImageZoomKey = "tabletImageZoom"
  private let tabletImageCropXKey = "tabletImageCropX"
  private let tabletImageCropYKey = "tabletImageCropY"

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

  // How strongly the custom image shows through the glass (0.1 faint – 1 solid).
  var tabletImageOpacity: Double {
    get {
      let value = defaults.object(forKey: tabletImageOpacityKey) == nil
        ? 0.55
        : defaults.double(forKey: tabletImageOpacityKey)
      return min(max(value, 0.1), 1)
    }
    set {
      defaults.set(min(max(newValue, 0.1), 1), forKey: tabletImageOpacityKey)
    }
  }

  // Uncropped source image + last crop parameters, kept so "Adjust Image..."
  // can reposition without re-importing.
  var tabletOriginalImagePath: String {
    get { defaults.string(forKey: tabletOriginalImagePathKey) ?? "" }
    set { defaults.set(newValue, forKey: tabletOriginalImagePathKey) }
  }

  var tabletImageZoom: Double {
    get {
      let value = defaults.object(forKey: tabletImageZoomKey) == nil ? 1 : defaults.double(forKey: tabletImageZoomKey)
      return min(max(value, 1), 3)
    }
    set { defaults.set(min(max(newValue, 1), 3), forKey: tabletImageZoomKey) }
  }

  var tabletImageCropX: Double {
    get { min(max(defaults.double(forKey: tabletImageCropXKey), -1), 1) }
    set { defaults.set(min(max(newValue, -1), 1), forKey: tabletImageCropXKey) }
  }

  var tabletImageCropY: Double {
    get { min(max(defaults.double(forKey: tabletImageCropYKey), -1), 1) }
    set { defaults.set(min(max(newValue, -1), 1), forKey: tabletImageCropYKey) }
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

  // When true, the Mac app pipes the raw Deepgram transcript through
  // /clean (OpenAI) before pasting. Off by default — Deepgram's
  // smart_format + dictation + filler-word strip covers the common cases
  // and skipping /clean shaves ~500-1500ms off paste latency.
  var polishWithGPT: Bool {
    get {
      defaults.bool(forKey: polishWithGPTKey)
    }
    set {
      defaults.set(newValue, forKey: polishWithGPTKey)
    }
  }

  // batch: record → /transcribe on stop (default, matches historical flow).
  // realtime: stream mic audio to /realtime and show words as they land.
  var transcriptionMode: TranscriptionMode {
    get {
      TranscriptionMode(rawValue: defaults.string(forKey: transcriptionModeKey) ?? "") ?? .batch
    }
    set {
      defaults.set(newValue.rawValue, forKey: transcriptionModeKey)
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

  // Raw multiline/comma text the user types in the Keywords tab.
  var keywordsText: String {
    get {
      defaults.string(forKey: keywordsTextKey) ?? ""
    }
    set {
      defaults.set(newValue, forKey: keywordsTextKey)
    }
  }

  // Parsed, de-duplicated keyterms forwarded to Deepgram as keyterm params.
  // Split on commas and newlines; trimmed; empties dropped.
  var keywords: [String] {
    var seen = Set<String>()
    var result: [String] = []
    for raw in keywordsText.components(separatedBy: CharacterSet(charactersIn: ",\n")) {
      let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !term.isEmpty, !seen.contains(term.lowercased()) else { continue }
      seen.insert(term.lowercased())
      result.append(term)
    }
    return result
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
    let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
    let destination = audioURL
      .appendingPathComponent("pending-\(UUID().uuidString)")
      .appendingPathExtension(ext)
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
    let originalURL = supportURL.appendingPathComponent("tablet-background-original.png")
    if FileManager.default.fileExists(atPath: originalURL.path) {
      try FileManager.default.removeItem(at: originalURL)
    }
  }

  // Copies the user's chosen file untouched so Adjust Image can re-crop from
  // full quality later. Extension is normalized away — NSImage sniffs content.
  func storeOriginal(from sourceURL: URL) throws -> URL {
    let destination = supportURL.appendingPathComponent("tablet-background-original.png")
    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.copyItem(at: sourceURL, to: destination)
    return destination
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

private func doubleValue(_ value: Any?) -> Double {
  if let double = value as? Double { return double }
  if let int = value as? Int { return Double(int) }
  if let number = value as? NSNumber { return number.doubleValue }
  if let string = value as? String, let parsed = Double(string) { return parsed }
  return 0
}

private func formatSeconds(_ seconds: Double) -> String {
  if seconds < 1 { return "0s" }
  if seconds < 60 { return "\(Int(seconds.rounded()))s" }
  let minutes = seconds / 60
  if minutes < 60 { return String(format: "%.1f min", minutes) }
  return String(format: "%.1f hr", minutes / 60)
}

private func formatTalkTime(_ value: Any?) -> String {
  formatSeconds(doubleValue(value))
}

// 100 WPM is the user's declared typing baseline for time-saved comparison.
private let typingWordsPerMinute: Double = 100

private func timeSavedString(_ wordCount: Any?) -> String {
  let words = Double(intValue(wordCount))
  if words <= 0 { return "0s" }
  return formatSeconds(words / typingWordsPerMinute * 60)
}
