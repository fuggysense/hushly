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

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private var tabletPanel: NSPanel!
  private var tabletView: TabletView!
  private var statusLabel: NSTextField!
  private var statusItem: NSStatusItem!
  private var settingsWindow: NSWindow?
  private var tabletTextField: NSTextField?
  private var shortcutPopup: NSPopUpButton?
  private var apiBaseField: NSTextField?
  private var hotKeyRef: EventHotKeyRef?
  private var eventHandlerRef: EventHandlerRef?
  private var recorder: AVAudioRecorder?
  private var recordingURL: URL?
  private var pasteTargetApp: NSRunningApplication?
  private var animationTimer: Timer?
  private var isRecording = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    buildStatusItem()
    buildTabletPanel()
    installHotKeyHandler()
    registerHotKey()
    showTabletPanel(positionAtBottom: true)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func windowWillClose(_ notification: Notification) {
    if notification.object as? NSWindow === settingsWindow {
      settingsWindow = nil
      tabletTextField = nil
      shortcutPopup = nil
      apiBaseField = nil
    }
  }

  private func buildStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.title = "hushly"

    let menu = NSMenu()
    menu.addItem(menuItem("Start / Stop Dictation", action: #selector(toggleDictation), key: "d"))
    menu.addItem(menuItem("Show Tablet", action: #selector(showTabletFromMenu), key: ""))
    menu.addItem(menuItem("Settings", action: #selector(showSettings), key: ","))
    menu.addItem(menuItem("Open Accessibility Settings", action: #selector(openAccessibilitySettings), key: ""))
    menu.addItem(.separator())
    menu.addItem(menuItem("Quit Hushly", action: #selector(NSApplication.terminate(_:)), key: "q"))
    statusItem.menu = menu
  }

  private func menuItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.target = self
    return item
  }

  private func buildTabletPanel() {
    let contentRect = NSRect(x: 0, y: 0, width: 460, height: 214)
    tabletPanel = NSPanel(
      contentRect: contentRect,
      styleMask: [.titled, .fullSizeContentView],
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
    tabletPanel.delegate = self
    tabletPanel.standardWindowButton(.closeButton)?.isHidden = true
    tabletPanel.standardWindowButton(.miniaturizeButton)?.isHidden = true
    tabletPanel.standardWindowButton(.zoomButton)?.isHidden = true

    let content = NSView(frame: contentRect)
    content.wantsLayer = true
    content.layer?.backgroundColor = NSColor(calibratedWhite: 0.02, alpha: 0.94).cgColor
    content.layer?.cornerRadius = 24
    content.layer?.masksToBounds = true

    tabletView = TabletView(frame: NSRect(x: 18, y: 46, width: 424, height: 150))
    tabletView.displayText = Preferences.shared.tabletText
    content.addSubview(tabletView)

    statusLabel = NSTextField(labelWithString: "Ready")
    statusLabel.frame = NSRect(x: 26, y: 20, width: 232, height: 18)
    statusLabel.textColor = NSColor.white.withAlphaComponent(0.72)
    statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
    statusLabel.lineBreakMode = .byTruncatingTail
    statusLabel.maximumNumberOfLines = 1
    content.addSubview(statusLabel)

    let dictateButton = NSButton(title: "Dictate", target: self, action: #selector(toggleDictation))
    dictateButton.frame = NSRect(x: 268, y: 14, width: 84, height: 28)
    dictateButton.bezelStyle = .rounded
    content.addSubview(dictateButton)

    let settingsButton = NSButton(title: "Settings", target: self, action: #selector(showSettings))
    settingsButton.frame = NSRect(x: 358, y: 14, width: 84, height: 28)
    settingsButton.bezelStyle = .rounded
    content.addSubview(settingsButton)

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
      y: visible.minY + 36
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

    pasteTargetApp = NSWorkspace.shared.frontmostApplication
    showTabletPanel(positionAtBottom: true)
    requestMicrophoneAccess { [weak self] granted in
      guard let self else { return }
      DispatchQueue.main.async {
        guard granted else {
          self.setStatus("Microphone permission is needed.")
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
      recorder.prepareToRecord()
      recorder.record()

      self.recorder = recorder
      self.recordingURL = fileURL
      self.isRecording = true
      self.tabletView.isRecording = true
      self.tabletView.displayText = Preferences.shared.tabletText
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

  private func processRecording(_ fileURL: URL) async {
    defer { try? FileManager.default.removeItem(at: fileURL) }

    do {
      let transcript = try await transcribe(fileURL: fileURL)
      guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        setStatus("No speech detected.")
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

      paste(finalText)
    } catch {
      setStatus(error.localizedDescription)
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
      setStatus("Clipboard ready. Access needed.")
      return
    }

    pasteTargetApp?.activate(options: [.activateAllWindows])
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
      let source = CGEventSource(stateID: .combinedSessionState)
      let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
      keyDown?.flags = .maskCommand
      keyUp?.flags = .maskCommand
      keyDown?.post(tap: .cghidEventTap)
      keyUp?.post(tap: .cghidEventTap)
      self.setStatus("Pasted")
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
    selectCurrentShortcut()
    NSApp.activate(ignoringOtherApps: true)
    window.center()
    window.makeKeyAndOrderFront(nil)
  }

  private func buildSettingsWindow() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 430, height: 250),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Hushly Settings"
    window.isReleasedWhenClosed = false
    window.delegate = self

    let content = NSView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 430, height: 250))

    let textLabel = NSTextField(labelWithString: "Tablet text")
    textLabel.frame = NSRect(x: 24, y: 188, width: 110, height: 18)
    content.addSubview(textLabel)

    let textField = NSTextField(string: Preferences.shared.tabletText)
    textField.frame = NSRect(x: 146, y: 182, width: 248, height: 28)
    content.addSubview(textField)
    tabletTextField = textField

    let shortcutLabel = NSTextField(labelWithString: "Shortcut")
    shortcutLabel.frame = NSRect(x: 24, y: 140, width: 110, height: 18)
    content.addSubview(shortcutLabel)

    let popup = NSPopUpButton(frame: NSRect(x: 146, y: 134, width: 248, height: 30), pullsDown: false)
    ShortcutCatalog.options.forEach { option in
      popup.addItem(withTitle: option.title)
      popup.lastItem?.representedObject = option.id
    }
    content.addSubview(popup)
    shortcutPopup = popup
    selectCurrentShortcut()

    let apiLabel = NSTextField(labelWithString: "API base")
    apiLabel.frame = NSRect(x: 24, y: 92, width: 110, height: 18)
    content.addSubview(apiLabel)

    let apiField = NSTextField(string: Preferences.shared.apiBase)
    apiField.frame = NSRect(x: 146, y: 86, width: 248, height: 28)
    content.addSubview(apiField)
    apiBaseField = apiField

    let hint = NSTextField(labelWithString: "Auto-paste requires macOS Accessibility permission.")
    hint.frame = NSRect(x: 24, y: 52, width: 370, height: 18)
    hint.textColor = NSColor.secondaryLabelColor
    hint.font = NSFont.systemFont(ofSize: 11)
    content.addSubview(hint)

    let saveButton = NSButton(title: "Save", target: self, action: #selector(saveSettings))
    saveButton.frame = NSRect(x: 300, y: 16, width: 94, height: 30)
    saveButton.bezelStyle = .rounded
    content.addSubview(saveButton)

    window.contentView = content
    settingsWindow = window
  }

  private func selectCurrentShortcut() {
    guard let popup = shortcutPopup else { return }
    if let item = popup.itemArray.first(where: { $0.representedObject as? String == Preferences.shared.shortcutID }) {
      popup.select(item)
    }
  }

  @objc private func saveSettings() {
    if let text = tabletTextField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
      Preferences.shared.tabletText = text
      tabletView.displayText = text
    }

    if let shortcutID = shortcutPopup?.selectedItem?.representedObject as? String {
      Preferences.shared.shortcutID = shortcutID
      registerHotKey()
    }

    if let apiBase = apiBaseField?.stringValue {
      Preferences.shared.apiBase = apiBase
    }

    setStatus("Settings saved")
    settingsWindow?.orderOut(nil)
    showTabletPanel(positionAtBottom: false)
  }

  private func installHotKeyHandler() {
    guard eventHandlerRef == nil else { return }

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, userData in
        guard let userData else { return noErr }
        let app = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
        DispatchQueue.main.async {
          app.toggleDictation()
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

    let shortcut = ShortcutCatalog.option(id: Preferences.shared.shortcutID)
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

  private func startGlowAnimation() {
    animationTimer?.invalidate()
    animationTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
      self?.tabletView.needsDisplay = true
    }
  }

  private func stopGlowAnimation() {
    animationTimer?.invalidate()
    animationTimer = nil
    tabletView.needsDisplay = true
  }

  private func setStatus(_ value: String) {
    DispatchQueue.main.async {
      self.statusLabel?.stringValue = value
      self.tabletView?.statusText = value
    }
  }

  private func playStartSound() {
    AudioServicesPlaySystemSound(SystemSoundID(1104))
  }

  private func playStopSound() {
    AudioServicesPlaySystemSound(SystemSoundID(1105))
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
    let rect = bounds.insetBy(dx: 10, dy: 10)
    let path = NSBezierPath(roundedRect: rect, xRadius: 28, yRadius: 28)
    NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.07, alpha: 0.92).setFill()
    path.fill()
    NSColor(calibratedRed: 0.18, green: 0.87, blue: 1, alpha: 0.75).setStroke()
    path.lineWidth = 2
    path.stroke()
  }

  private func drawGlow() {
    let stroke = NSBezierPath(roundedRect: bounds.insetBy(dx: 14, dy: 14), xRadius: 26, yRadius: 26)
    (isRecording
      ? NSColor(calibratedRed: 0.20, green: 0.95, blue: 1, alpha: 0.55)
      : NSColor(calibratedRed: 0.55, green: 0.32, blue: 1, alpha: 0.34)
    ).setStroke()
    stroke.lineWidth = isRecording ? 3 : 1.5
    stroke.stroke()
  }

  private func drawDisplayText() {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byTruncatingTail

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedRed: 0.10, green: 0.92, blue: 1, alpha: 0.88)
    shadow.shadowBlurRadius = isRecording ? 16 : 8
    shadow.shadowOffset = .zero

    let font = NSFont.systemFont(ofSize: 32, weight: .heavy)
    let attrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: NSColor.white,
      .paragraphStyle: paragraph,
      .shadow: shadow,
    ]

    let textRect = NSRect(x: 38, y: bounds.midY - 19, width: bounds.width - 76, height: 42)
    displayText.draw(in: textRect, withAttributes: attrs)
  }

  private func drawWaveform() {
    let barCount = 18
    let totalWidth: CGFloat = 188
    let startX = bounds.midX - (totalWidth / 2)
    let baseY: CGFloat = 30
    let phase = CGFloat(Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10))

    for index in 0..<barCount {
      let x = startX + CGFloat(index) * (totalWidth / CGFloat(barCount))
      let pulse = sin((CGFloat(index) * 0.85) + (phase * 7))
      let height = isRecording ? 10 + max(0, pulse) * 20 : 5
      let rect = NSRect(x: x, y: baseY, width: 5, height: height)
      let path = NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5)
      NSColor(calibratedRed: 0.18, green: 0.92, blue: 1, alpha: isRecording ? 0.95 : 0.34).setFill()
      path.fill()
    }
  }
}

final class Preferences {
  static let shared = Preferences()

  private let defaults = UserDefaults.standard
  private let tabletTextKey = "tabletText"
  private let shortcutIDKey = "shortcutID"
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
