import AVFoundation
import Foundation

// Live transcription session: taps the mic with AVAudioEngine, downsamples to
// 16 kHz mono Int16 PCM, streams it to the VPS /realtime WebSocket proxy, and
// surfaces Deepgram interim/final transcripts through callbacks. Also writes
// the tapped audio to a local WAV so History keeps a retry copy, matching the
// batch pipeline's behavior.
final class RealtimeSession: NSObject, @unchecked Sendable {
  var onInterim: ((String) -> Void)?
  var onFinal: ((String) -> Void)?
  var onLevel: ((CGFloat) -> Void)?
  var onError: ((String) -> Void)?

  private(set) var finalSegments: [String] = []
  private(set) var lastInterim = ""
  private(set) var recordingURL: URL?

  private let engine = AVAudioEngine()
  private var socket: URLSessionWebSocketTask?
  private var converter: AVAudioConverter?
  // audioFile is only touched on fileQueue so tap-thread writes can't race
  // the close in stopEngine().
  private var audioFile: AVAudioFile?
  private let fileQueue = DispatchQueue(label: "hushly.realtime.audiofile")
  private var closed = false
  // Main-thread-only state for the finalize handshake.
  private var socketDone = false
  private var finalizeContinuation: CheckedContinuation<Void, Never>?

  private static let targetFormat = AVAudioFormat(
    commonFormat: .pcmFormatInt16,
    sampleRate: 16_000,
    channels: 1,
    interleaved: true
  )!

  func start(url: URL, apiKey: String) throws {
    var request = URLRequest(url: url)
    if !apiKey.isEmpty {
      request.setValue(apiKey, forHTTPHeaderField: "X-Hushly-API-Key")
    }
    let task = URLSession.shared.webSocketTask(with: request)
    socket = task
    task.resume()
    receiveNextMessage()

    let input = engine.inputNode
    let inputFormat = input.outputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
      throw HushlyError.api("No microphone input available")
    }
    converter = AVAudioConverter(from: inputFormat, to: Self.targetFormat)

    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("hushly-live-\(UUID().uuidString)")
      .appendingPathExtension("wav")
    let file = try AVAudioFile(forWriting: fileURL, settings: Self.targetFormat.settings)
    fileQueue.sync { audioFile = file }
    recordingURL = fileURL

    input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
      self?.handleTap(buffer)
    }
    engine.prepare()
    try engine.start()
  }

  // Finish speaking: stop the mic, ask the server to flush Deepgram's final
  // results, and wait (bounded) for the socket to close so no trailing words
  // are lost. Returns the assembled transcript.
  func finalize() async -> String {
    stopEngine()
    send(text: "{\"type\":\"finalize\"}")

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      DispatchQueue.main.async { [weak self] in
        guard let self, !self.socketDone else {
          // Socket already failed/closed (e.g. auth rejection) — no more
          // results are coming, don't sit out the timeout.
          continuation.resume()
          return
        }
        self.finalizeContinuation = continuation
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
          self?.resumeFinalize()
        }
      }
    }

    closeSocket()
    // Transcript segments are appended on main; read them there too.
    return await MainActor.run { transcript() }
  }

  // Abort without waiting for results (Escape / cancel-for-retry).
  func cancel() {
    stopEngine()
    closeSocket()
    resumeFinalize()
  }

  func transcript() -> String {
    var parts = finalSegments
    let interim = lastInterim.trimmingCharacters(in: .whitespacesAndNewlines)
    if !interim.isEmpty {
      parts.append(interim)
    }
    return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var liveDisplayText: String {
    var parts = finalSegments
    if !lastInterim.isEmpty {
      parts.append(lastInterim)
    }
    return parts.joined(separator: " ")
  }

  private func handleTap(_ buffer: AVAudioPCMBuffer) {
    reportLevel(from: buffer)

    guard let converter else { return }
    let ratio = Self.targetFormat.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 32)
    guard let converted = AVAudioPCMBuffer(pcmFormat: Self.targetFormat, frameCapacity: capacity) else { return }

    var fed = false
    var conversionError: NSError?
    converter.convert(to: converted, error: &conversionError) { _, outStatus in
      if fed {
        outStatus.pointee = .noDataNow
        return nil
      }
      fed = true
      outStatus.pointee = .haveData
      return buffer
    }
    guard conversionError == nil, converted.frameLength > 0 else { return }

    fileQueue.async { [weak self] in
      try? self?.audioFile?.write(from: converted)
    }

    guard let channel = converted.int16ChannelData else { return }
    let data = Data(bytes: channel[0], count: Int(converted.frameLength) * MemoryLayout<Int16>.size)
    socket?.send(.data(data)) { _ in }
  }

  private func reportLevel(from buffer: AVAudioPCMBuffer) {
    guard let channel = buffer.floatChannelData, buffer.frameLength > 0 else { return }
    var sum: Float = 0
    let frames = Int(buffer.frameLength)
    for index in 0..<frames {
      let sample = channel[0][index]
      sum += sample * sample
    }
    let rms = sqrt(sum / Float(frames))
    // Map roughly -50dB..0dB onto 0..1 like the batch recorder's meter curve.
    let db = 20 * log10(max(rms, 0.000_01))
    let normalized = max(0, min(1, CGFloat((db + 50) / 50)))
    DispatchQueue.main.async { [weak self] in
      self?.onLevel?(normalized)
    }
  }

  private func receiveNextMessage() {
    socket?.receive { [weak self] result in
      guard let self else { return }
      switch result {
      case .failure:
        // Socket closed (server finished or connection dropped).
        DispatchQueue.main.async { self.socketDone = true }
        self.resumeFinalize()
      case .success(let message):
        if case .string(let text) = message {
          self.handleServerEvent(text)
        }
        self.receiveNextMessage()
      }
    }
  }

  private func handleServerEvent(_ raw: String) {
    guard
      let data = raw.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let type = json["type"] as? String
    else {
      return
    }

    switch type {
    case "interim":
      let text = json["text"] as? String ?? ""
      DispatchQueue.main.async { [weak self] in
        self?.lastInterim = text
        self?.onInterim?(text)
      }
    case "final":
      let text = (json["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        if !text.isEmpty {
          self.finalSegments.append(text)
        }
        self.lastInterim = ""
        self.onFinal?(text)
      }
    case "error":
      let message = json["error"] as? String ?? "realtime error"
      DispatchQueue.main.async { [weak self] in
        self?.onError?(message)
      }
    default:
      break
    }
  }

  private func stopEngine() {
    engine.inputNode.removeTap(onBus: 0)
    if engine.isRunning {
      engine.stop()
    }
    // Drain queued writes, then close the file, before anyone copies it.
    fileQueue.sync { audioFile = nil }
  }

  private func send(text: String) {
    socket?.send(.string(text)) { _ in }
  }

  private func closeSocket() {
    guard !closed else { return }
    closed = true
    socket?.cancel(with: .normalClosure, reason: nil)
    socket = nil
  }

  private func resumeFinalize() {
    DispatchQueue.main.async { [weak self] in
      guard let self, let continuation = self.finalizeContinuation else { return }
      self.finalizeContinuation = nil
      continuation.resume()
    }
  }
}
