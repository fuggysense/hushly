import UIKit
import AVFoundation

// hushly keyboard extension
//
// Tap-to-toggle dictation that lives inside any iOS text field.
// Records via AVAudioRecorder → chunked POST to /transcribe → final POST to /clean
// → inserts cleaned text into the host app's text field via UITextDocumentProxy.
//
// REQUIREMENTS for this to function:
//   • Info.plist: NSExtensionAttributes.RequestsOpenAccess = YES
//   • User flips Settings → General → Keyboards → hushly → Allow Full Access
//   • App Group entitlement matches the main app (so we can read the
//     Supabase JWT written by the main app at sign-in time).

final class KeyboardViewController: UIInputViewController {

  // MARK: - Config

  private let apiBase = "https://hushly-six.vercel.app"
  private let appGroup = "group.app.hushly"  // must match main app's entitlement

  // MARK: - UI

  private let recordButton = UIButton(type: .system)
  private let statusLabel = UILabel()
  private let nextKeyboardButton = UIButton(type: .system)

  // MARK: - Audio

  private var audioRecorder: AVAudioRecorder?
  private var currentRecordingURL: URL?
  private var chunkTimer: Timer?
  private let chunkSeconds: TimeInterval = 2.5
  private var partials: [String] = []
  private var recordStart: Date?
  private var isRecording = false

  // MARK: - Lifecycle

  override func viewDidLoad() {
    super.viewDidLoad()
    setupUI()
  }

  private func setupUI() {
    view.backgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1)

    recordButton.translatesAutoresizingMaskIntoConstraints = false
    recordButton.setTitle("Tap to record", for: .normal)
    recordButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
    recordButton.setTitleColor(.white, for: .normal)
    recordButton.backgroundColor = UIColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1)
    recordButton.layer.cornerRadius = 30
    recordButton.addTarget(self, action: #selector(toggleRecord), for: .touchUpInside)
    view.addSubview(recordButton)

    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    statusLabel.font = .systemFont(ofSize: 12)
    statusLabel.textColor = UIColor(white: 0.6, alpha: 1)
    statusLabel.textAlignment = .center
    statusLabel.text = "ready"
    view.addSubview(statusLabel)

    nextKeyboardButton.translatesAutoresizingMaskIntoConstraints = false
    nextKeyboardButton.setTitle("🌐", for: .normal)
    nextKeyboardButton.titleLabel?.font = .systemFont(ofSize: 22)
    nextKeyboardButton.addTarget(self,
                                 action: #selector(handleInputModeList(from:with:)),
                                 forEvent: .allTouchEvents)
    view.addSubview(nextKeyboardButton)

    NSLayoutConstraint.activate([
      recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      recordButton.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 8),
      recordButton.widthAnchor.constraint(equalToConstant: 240),
      recordButton.heightAnchor.constraint(equalToConstant: 60),

      statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      statusLabel.bottomAnchor.constraint(equalTo: recordButton.topAnchor, constant: -12),

      nextKeyboardButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      nextKeyboardButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
    ])
  }

  // MARK: - Record toggle

  @objc private func toggleRecord() {
    if isRecording {
      stopAndFinalize()
    } else {
      startRecording()
    }
  }

  private func startRecording() {
    guard hasFullAccess else {
      statusLabel.text = "Enable Full Access in Settings"
      return
    }

    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
      try session.setActive(true)
    } catch {
      statusLabel.text = "mic init failed"
      return
    }

    AVAudioApplication.requestRecordPermission { [weak self] granted in
      DispatchQueue.main.async {
        guard let self = self else { return }
        if !granted {
          self.statusLabel.text = "mic permission denied"
          return
        }
        self.beginSegment()
        self.recordStart = Date()
        self.partials.removeAll()
        self.isRecording = true
        self.recordButton.setTitle("Tap to stop", for: .normal)
        self.recordButton.backgroundColor = UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1)
        self.statusLabel.text = "listening…"
        self.chunkTimer = Timer.scheduledTimer(
          withTimeInterval: self.chunkSeconds, repeats: true
        ) { _ in self.rotateSegment() }
      }
    }
  }

  private func beginSegment() {
    let dir = FileManager.default.temporaryDirectory
    let url = dir.appendingPathComponent(UUID().uuidString + ".m4a")
    currentRecordingURL = url

    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: 44100,
      AVNumberOfChannelsKey: 1,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]
    do {
      audioRecorder = try AVAudioRecorder(url: url, settings: settings)
      audioRecorder?.record()
    } catch {
      statusLabel.text = "rec failed"
    }
  }

  private func rotateSegment() {
    guard isRecording else { return }
    let finishedURL = currentRecordingURL
    audioRecorder?.stop()
    beginSegment()

    if let url = finishedURL {
      Task { await transcribeChunk(url: url, isFinal: false) }
    }
  }

  private func stopAndFinalize() {
    isRecording = false
    chunkTimer?.invalidate()
    chunkTimer = nil
    audioRecorder?.stop()
    // Drop the un-rotated final segment to keep finalize <2s.
    recordButton.setTitle("…cleaning", for: .normal)
    recordButton.backgroundColor = UIColor(white: 0.3, alpha: 1)
    statusLabel.text = "cleaning…"

    Task {
      // Wait a moment for in-flight chunk transcribes to land
      try? await Task.sleep(nanoseconds: 600_000_000)
      let raw = await MainActor.run { self.partials.joined(separator: " ") }
      if raw.isEmpty {
        await MainActor.run { self.resetUI(message: "no speech") }
        return
      }
      let cleaned = await self.cleanText(raw)
      await MainActor.run {
        self.textDocumentProxy.insertText(cleaned)
        self.resetUI(message: "✓ inserted")
      }
    }
  }

  private func resetUI(message: String) {
    recordButton.setTitle("Tap to record", for: .normal)
    recordButton.backgroundColor = UIColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1)
    statusLabel.text = message
  }

  // MARK: - Network

  private func transcribeChunk(url: URL, isFinal: Bool) async {
    do {
      let data = try Data(contentsOf: url)
      var req = URLRequest(url: URL(string: apiBase + "/transcribe")!)
      req.httpMethod = "POST"
      req.setValue("audio/m4a", forHTTPHeaderField: "Content-Type")
      req.httpBody = data
      let (respData, _) = try await URLSession.shared.data(for: req)
      if let json = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
         let text = json["transcript"] as? String, !text.isEmpty {
        await MainActor.run {
          self.partials.append(text)
        }
      }
    } catch {
      // swallow — chunk drop is acceptable
    }
    try? FileManager.default.removeItem(at: url)
  }

  private func cleanText(_ raw: String) async -> String {
    do {
      var req = URLRequest(url: URL(string: apiBase + "/clean")!)
      req.httpMethod = "POST"
      req.setValue("application/json", forHTTPHeaderField: "Content-Type")
      req.httpBody = try JSONSerialization.data(withJSONObject: ["text": raw])
      let (respData, _) = try await URLSession.shared.data(for: req)
      if let json = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
         let cleaned = json["cleaned"] as? String, !cleaned.isEmpty {
        return cleaned
      }
    } catch {
      // fall through
    }
    return raw
  }
}
