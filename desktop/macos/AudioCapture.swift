import AVFoundation
import CoreAudio
import Foundation

// Everything to do with *which* microphone we capture from, and the batch-mode
// engine recorder that honors that choice. Realtime capture lives in
// RealtimeSession; both funnel through AudioDeviceManager.apply so a mic picked
// in Settings routes both modes away from any virtual/system-audio input.

struct AudioInputDevice: Equatable {
  let id: AudioDeviceID
  let uid: String
  let name: String
}

struct AudioOutputDevice: Equatable {
  let id: AudioDeviceID
  let uid: String
  let name: String
}

enum AudioDeviceManager {
  // All input devices CoreAudio can see, in HAL order. Excludes output-only
  // devices (no input streams) so the picker never lists e.g. the speakers.
  static func inputDevices() -> [AudioInputDevice] {
    var address = propertyAddress(kAudioHardwarePropertyDevices)
    var dataSize: UInt32 = 0
    guard
      AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr,
      dataSize > 0
    else { return [] }

    let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    var ids = [AudioDeviceID](repeating: 0, count: count)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &ids) == noErr
    else { return [] }

    return ids.compactMap { id in
      guard hasInputStreams(id), let uid = stringProperty(id, kAudioDevicePropertyDeviceUID)
      else { return nil }
      let name = stringProperty(id, kAudioObjectPropertyName) ?? "Microphone"
      return AudioInputDevice(id: id, uid: uid, name: name)
    }
  }

  // Human-readable name of the current system default input, for the "System
  // default (…)" label in the picker.
  static func defaultInputDeviceName() -> String? {
    var address = propertyAddress(kAudioHardwarePropertyDefaultInputDevice)
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
      deviceID != 0
    else { return nil }
    return stringProperty(deviceID, kAudioObjectPropertyName)
  }

  static func deviceID(forUID uid: String) -> AudioDeviceID? {
    inputDevices().first(where: { $0.uid == uid })?.id
  }

  static func defaultInputDeviceID() -> AudioDeviceID? {
    var address = propertyAddress(kAudioHardwarePropertyDefaultInputDevice)
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
      deviceID != 0
    else { return nil }
    return deviceID
  }

  static func transportType(_ id: AudioDeviceID) -> UInt32 {
    var address = propertyAddress(kAudioDevicePropertyTransportType)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return 0 }
    return value
  }

  // A Bluetooth mic is the one input that can't coexist with music on the same
  // earpiece: opening it forces the headset from A2DP (stereo playback) into
  // HFP/SCO (mono call mode), which drops or degrades whatever's playing. USB /
  // built-in mics are independent HAL devices and never touch the earpiece.
  static func isBluetooth(_ id: AudioDeviceID) -> Bool {
    let t = transportType(id)
    return t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
  }

  // Which mic to actually open. An explicit selection always wins (the user
  // asked for it). In System-default mode, if the default input is a Bluetooth
  // earpiece, capturing from it would interrupt music playing on that same
  // earpiece — so fall back to the first non-Bluetooth input instead. Empty
  // return means "the system default is safe, let the engine use it."
  static func resolveCaptureUID(selected uid: String) -> String {
    if !uid.isEmpty { return uid }
    guard let defaultID = defaultInputDeviceID(), isBluetooth(defaultID) else { return "" }
    return inputDevices().first(where: { !isBluetooth($0.id) })?.uid ?? ""
  }

  // Point an AVAudioEngine's input node at the chosen device. Empty UID (or a
  // device that has since disappeared) is a no-op, so we fall back to the
  // system default. Must be called before reading the input format / starting.
  static func apply(uid: String, to engine: AVAudioEngine) {
    guard !uid.isEmpty, let id = deviceID(forUID: uid) else { return }
    guard let audioUnit = engine.inputNode.audioUnit else { return }
    var deviceID = id
    AudioUnitSetProperty(
      audioUnit,
      kAudioOutputUnitProperty_CurrentDevice,
      kAudioUnitScope_Global,
      0,
      &deviceID,
      UInt32(MemoryLayout<AudioDeviceID>.size))
  }

  // Output devices CoreAudio can see (excludes input-only), for the "Output"
  // picker. Selecting one flips the *system* default output — Hushly doesn't own
  // a private playback device, it just changes the OS default so e.g. AirPods
  // stay your listening device while a separate mic feeds capture.
  static func outputDevices() -> [AudioOutputDevice] {
    var address = propertyAddress(kAudioHardwarePropertyDevices)
    var dataSize: UInt32 = 0
    guard
      AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr,
      dataSize > 0
    else { return [] }

    let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    var ids = [AudioDeviceID](repeating: 0, count: count)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &ids) == noErr
    else { return [] }

    return ids.compactMap { id in
      guard hasOutputStreams(id), let uid = stringProperty(id, kAudioDevicePropertyDeviceUID)
      else { return nil }
      let name = stringProperty(id, kAudioObjectPropertyName) ?? "Speaker"
      return AudioOutputDevice(id: id, uid: uid, name: name)
    }
  }

  static func defaultOutputDeviceID() -> AudioDeviceID? {
    var address = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
      deviceID != 0
    else { return nil }
    return deviceID
  }

  // UID of the current system default output, so the picker can preselect it.
  static func defaultOutputDeviceUID() -> String? {
    guard let id = defaultOutputDeviceID() else { return nil }
    return stringProperty(id, kAudioDevicePropertyDeviceUID)
  }

  // True when you're listening through a Bluetooth device. Used to suppress
  // Hushly's own feedback sounds there: opening a short playback stream on a BT
  // earpiece renegotiates its A2DP link and audibly stops/resumes any music.
  static func isDefaultOutputBluetooth() -> Bool {
    guard let id = defaultOutputDeviceID() else { return false }
    return isBluetooth(id)
  }

  // Flip the system default output to the chosen device. Returns false if the
  // UID no longer resolves (device unplugged) so the caller can resync the list.
  @discardableResult
  static func setDefaultOutputDevice(uid: String) -> Bool {
    guard let id = outputDevices().first(where: { $0.uid == uid })?.id else { return false }
    var deviceID = id
    var address = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
    return AudioObjectSetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
      UInt32(MemoryLayout<AudioDeviceID>.size), &deviceID) == noErr
  }

  private static func propertyAddress(
    _ selector: AudioObjectPropertySelector,
    _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
  }

  private static func hasInputStreams(_ id: AudioDeviceID) -> Bool {
    var address = propertyAddress(
      kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyScopeInput)
    var dataSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &dataSize) == noErr, dataSize > 0
    else { return false }

    let buffer = UnsafeMutableRawPointer.allocate(
      byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { buffer.deallocate() }
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &dataSize, buffer) == noErr else {
      return false
    }
    let list = UnsafeMutableAudioBufferListPointer(
      buffer.assumingMemoryBound(to: AudioBufferList.self))
    return list.contains { $0.mNumberChannels > 0 }
  }

  private static func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
    var address = propertyAddress(
      kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyScopeOutput)
    var dataSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &dataSize) == noErr, dataSize > 0
    else { return false }

    let buffer = UnsafeMutableRawPointer.allocate(
      byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { buffer.deallocate() }
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &dataSize, buffer) == noErr else {
      return false
    }
    let list = UnsafeMutableAudioBufferListPointer(
      buffer.assumingMemoryBound(to: AudioBufferList.self))
    return list.contains { $0.mNumberChannels > 0 }
  }

  private static func stringProperty(
    _ id: AudioDeviceID, _ selector: AudioObjectPropertySelector
  ) -> String? {
    var address = propertyAddress(selector)
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var value: Unmanaged<CFString>?
    let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
    guard status == noErr, let value else { return nil }
    // CoreAudio hands back a +1 retained CFString for these properties.
    return value.takeRetainedValue() as String
  }
}

// Shared 16 kHz mono Int16 PCM conversion + metering, so the batch recorder and
// the realtime session agree on the exact wire/file format Deepgram expects.
enum PCM16 {
  static let format = AVAudioFormat(
    commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!

  static func convert(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter)
    -> AVAudioPCMBuffer?
  {
    let ratio = format.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 32)
    guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
      return nil
    }
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
    guard conversionError == nil, converted.frameLength > 0 else { return nil }
    return converted
  }

  // Map roughly -50dB..0dB onto 0..1 like the batch recorder's old meter curve.
  static func level(from buffer: AVAudioPCMBuffer) -> CGFloat? {
    guard let channel = buffer.floatChannelData, buffer.frameLength > 0 else { return nil }
    var sum: Float = 0
    let frames = Int(buffer.frameLength)
    for index in 0..<frames {
      let sample = channel[0][index]
      sum += sample * sample
    }
    let rms = sqrt(sum / Float(frames))
    let db = 20 * log10(max(rms, 0.000_01))
    return max(0, min(1, CGFloat((db + 50) / 50)))
  }
}

// Batch dictation recorder: taps the selected input device with AVAudioEngine
// and writes a 16 kHz mono Int16 WAV (uploaded to /transcribe as audio/wav on
// stop). Replaces AVAudioRecorder so device selection works in batch mode too.
// The AVAudioFile is pinned to Int16/interleaved for the same reason
// RealtimeSession is — the settings-only initializer defaults processingFormat
// to deinterleaved Float32 and CoreAudio traps (SIGTRAP) on the first write.
final class EngineRecorder: NSObject, @unchecked Sendable {
  var onLevel: ((CGFloat) -> Void)?
  private(set) var recordingURL: URL?

  private let engine = AVAudioEngine()
  private var converter: AVAudioConverter?
  private var audioFile: AVAudioFile?
  private let fileQueue = DispatchQueue(label: "hushly.batch.audiofile")

  func start(inputDeviceUID: String) throws {
    let input = engine.inputNode
    AudioDeviceManager.apply(uid: inputDeviceUID, to: engine)
    let inputFormat = input.outputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
      throw HushlyError.api("No microphone input available")
    }
    converter = AVAudioConverter(from: inputFormat, to: PCM16.format)

    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("hushly-\(UUID().uuidString)")
      .appendingPathExtension("wav")
    let file = try AVAudioFile(
      forWriting: fileURL,
      settings: PCM16.format.settings,
      commonFormat: .pcmFormatInt16,
      interleaved: true)
    fileQueue.sync { audioFile = file }
    recordingURL = fileURL

    input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
      self?.handleTap(buffer)
    }
    engine.prepare()
    try engine.start()
  }

  func stop() {
    engine.inputNode.removeTap(onBus: 0)
    if engine.isRunning {
      engine.stop()
    }
    // Drain queued writes, then close the file, before anyone reads it.
    fileQueue.sync { audioFile = nil }
  }

  private func handleTap(_ buffer: AVAudioPCMBuffer) {
    if let level = PCM16.level(from: buffer) {
      DispatchQueue.main.async { [weak self] in self?.onLevel?(level) }
    }
    guard let converter, let converted = PCM16.convert(buffer, using: converter) else { return }
    fileQueue.async { [weak self] in
      try? self?.audioFile?.write(from: converted)
    }
  }
}
