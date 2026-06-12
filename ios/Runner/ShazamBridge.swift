import Flutter
import Foundation
import ShazamKit
import AVFoundation

/// Native side of the `audio_dashcam/shazam` MethodChannel. Identifies a song
/// from a short clip of PCM16 the Dart layer captured, using Apple's ShazamKit.
///
/// Requires the ShazamKit capability on the Runner target. The clip is converted
/// to a `SHSignature` and matched against Apple's catalog; only the derived
/// signature is sent. Returns `{title, artist}` or nil when nothing matches.
@available(iOS 15.0, *)
final class ShazamBridge: NSObject {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "audio_dashcam/shazam",
      binaryMessenger: messenger
    )
    let instance = ShazamBridge()
    channel.setMethodCallHandler { call, result in
      instance.handle(call, result: result)
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "match":
      guard
        let args = call.arguments as? [String: Any],
        let payload = args["pcm"] as? FlutterStandardTypedData,
        let sampleRate = args["sampleRate"] as? Int,
        let channels = args["channels"] as? Int
      else {
        result(FlutterError(code: "bad_args", message: "pcm, sampleRate, channels required", details: nil))
        return
      }
      match(pcm: payload.data, sampleRate: Double(sampleRate), channels: channels, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func match(pcm: Data, sampleRate: Double, channels: Int, result: @escaping FlutterResult) {
    guard let buffer = makeBuffer(pcm: pcm, sampleRate: sampleRate, channels: channels) else {
      result(nil)
      return
    }
    let generator = SHSignatureGenerator()
    do {
      try generator.append(buffer, at: nil)
      let signature = generator.signature()
      let session = SHSession()
      // Retain both the session and its delegate until the match completes;
      // support overlapping requests by keeping a set rather than one slot.
      let delegate = MatchDelegate { [weak self] value in
        result(value)
        self?.finish(session)
      }
      pending[ObjectIdentifier(session)] = (session, delegate)
      session.delegate = delegate
      session.match(signature)
    } catch {
      result(nil)
    }
  }

  private func finish(_ session: SHSession) {
    pending.removeValue(forKey: ObjectIdentifier(session))
  }

  private var pending: [ObjectIdentifier: (SHSession, MatchDelegate)] = [:]

  private func makeBuffer(pcm: Data, sampleRate: Double, channels: Int) -> AVAudioPCMBuffer? {
    guard
      let format = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: sampleRate,
        channels: AVAudioChannelCount(max(1, channels)),
        interleaved: true
      )
    else { return nil }
    let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
    let frameCount = pcm.count / max(1, bytesPerFrame)
    guard frameCount > 0,
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))
    else { return nil }
    buffer.frameLength = AVAudioFrameCount(frameCount)
    if let dst = buffer.int16ChannelData {
      pcm.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        if let src = raw.bindMemory(to: Int16.self).baseAddress {
          dst[0].update(from: src, count: frameCount * max(1, channels))
        }
      }
    }
    return buffer
  }
}

@available(iOS 15.0, *)
private final class MatchDelegate: NSObject, SHSessionDelegate {
  init(onResult: @escaping (Any?) -> Void) {
    self.onResult = onResult
  }

  private let onResult: (Any?) -> Void
  private var responded = false

  func session(_ session: SHSession, didFind match: SHMatch) {
    guard let item = match.mediaItems.first else {
      respond(nil)
      return
    }
    respond(["title": item.title ?? "", "artist": item.artist ?? ""])
  }

  func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
    respond(nil)
  }

  private func respond(_ value: Any?) {
    if responded { return }
    responded = true
    onResult(value)
  }
}
