import Cocoa
import Carbon.HIToolbox
import WebKit

private let appURL = URL(string: "https://hushly-six.vercel.app")!

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKUIDelegate {
  private var window: NSWindow!
  private var statusItem: NSStatusItem!
  private var webView: WKWebView!
  private var hotKeyRef: EventHotKeyRef?
  private var eventHandlerRef: EventHandlerRef?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    buildStatusItem()
    buildWindow()
    registerHotKey()
    showWindow()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func windowWillClose(_ notification: Notification) {
    NSApp.hide(nil)
  }

  private func buildStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.title = "hushly"
    statusItem.button?.action = #selector(toggleWindow)
    statusItem.button?.target = self

    let menu = NSMenu()
    menu.addItem(NSMenuItem(title: "Show Hushly", action: #selector(showWindow), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: "Reload", action: #selector(reload), keyEquivalent: "r"))
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "Quit Hushly", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    statusItem.menu = menu
  }

  private func buildWindow() {
    let config = WKWebViewConfiguration()
    config.defaultWebpagePreferences.allowsContentJavaScript = true
    config.mediaTypesRequiringUserActionForPlayback = []

    webView = WKWebView(frame: .zero, configuration: config)
    webView.uiDelegate = self
    webView.load(URLRequest(url: appURL))

    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 680),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = "hushly"
    window.contentView = webView
    window.delegate = self
    window.level = .floating
    window.isReleasedWhenClosed = false
    window.titlebarAppearsTransparent = true
    window.standardWindowButton(.zoomButton)?.isHidden = true
  }

  @objc private func toggleWindow() {
    if window.isVisible && NSApp.isActive {
      window.orderOut(nil)
      NSApp.hide(nil)
    } else {
      showWindow()
    }
  }

  @objc private func showWindow() {
    if window == nil { buildWindow() }
    NSApp.unhide(nil)
    NSApp.activate(ignoringOtherApps: true)
    window.center()
    window.makeKeyAndOrderFront(nil)
  }

  @objc private func reload() {
    webView.reload()
    showWindow()
  }

  private func registerHotKey() {
    let hotKeyID = EventHotKeyID(signature: fourCharCode("hush"), id: 1)
    RegisterEventHotKey(
      UInt32(kVK_Space),
      UInt32(controlKey | optionKey),
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, userData in
        guard let userData else { return noErr }
        let app = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
        app.showWindow()
        return noErr
      },
      1,
      &eventType,
      UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
      &eventHandlerRef
    )
  }

  private func fourCharCode(_ value: String) -> OSType {
    value.utf8.reduce(0) { ($0 << 8) + OSType($1) }
  }

  @available(macOS 12.0, *)
  func webView(
    _ webView: WKWebView,
    requestMediaCapturePermissionFor origin: WKSecurityOrigin,
    initiatedByFrame frame: WKFrameInfo,
    type: WKMediaCaptureType,
    decisionHandler: @escaping (WKPermissionDecision) -> Void
  ) {
    decisionHandler(.grant)
  }
}
