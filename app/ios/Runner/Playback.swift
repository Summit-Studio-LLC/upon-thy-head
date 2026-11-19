import AVFoundation
import Flutter
import MediaPlayer
import UIKit

/// Plays a blessing's recording back on the review page (lib/review/player.dart), on the channel
/// `upon_thy_head/player`.
///
/// Methods (Dart → iOS):
///  - `load` {path} → duration in seconds; stops whatever was loaded before
///  - `play` → true if it started (false when the system will not give the app its audio, e.g. a call)
///  - `pause`
///  - `seek` {seconds}
///  - `position` → {"position", "duration", "playing"}
///  - `unload` : stop, forget the file, and give the audio back to other apps
/// Events (iOS → Dart): `stopped` {position} when playback ends or the system takes the audio.
///
/// The audio session is `.playback` with the `.spokenAudio` mode and no mixing: playing pauses
/// other apps' audio (a podcast, music) as any player does, and lets them resume after. It never
/// interrupts a phone call: the system refuses to activate a non-mixing session during a call,
/// and `play` then answers false. A call or Siri during playback pauses it.
///
/// Playing carries on while the phone is locked or the app is in the background (the app declares
/// background audio, Info.plist). Nothing about the blessing is told to the system: no Now Playing
/// title, artwork or controls, so with the phone locked the lock screen shows nothing of it.
enum Playback {
  static var channel: FlutterMethodChannel?
  private static var player: AVAudioPlayer?
  private static let delegate = Delegate()
  private static var observing = false

  static func register(messenger: FlutterBinaryMessenger) {
    let c = FlutterMethodChannel(name: "upon_thy_head/player", binaryMessenger: messenger)
    c.setMethodCallHandler(handle)
    channel = c
  }

  static func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "load":
      guard let path = args["path"] as? String else { return result(FlutterError(code: "args", message: "path", details: nil)) }
      unload()
      do {
        let p = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
        p.delegate = delegate
        p.prepareToPlay()
        player = p
        result(p.duration)
      } catch {
        result(FlutterError(code: "load", message: "\(error)", details: nil))
      }
    case "play":
      guard let p = player else { return result(false) }
      let session = AVAudioSession.sharedInstance()
      do {
        try session.setCategory(.playback, mode: .spokenAudio, options: [])
        try session.setActive(true)
      } catch {
        NSLog("player: the system kept the audio: %@", "\(error)")
        return result(false)
      }
      if !observing {
        observing = true
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { n in
          guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                AVAudioSession.InterruptionType(rawValue: raw) == .began, let p = player, p.isPlaying else { return }
          p.pause()
          channel?.invokeMethod("stopped", arguments: ["position": p.currentTime])
        }
        nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { n in
          guard let raw = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable,
                let p = player, p.isPlaying else { return }
          p.pause()
          channel?.invokeMethod("stopped", arguments: ["position": p.currentTime])
        }
      }
      if p.currentTime >= p.duration - 0.05 { p.currentTime = 0 }
      hideFromLockScreen()
      result(p.play())
    case "pause":
      player?.pause()
      result(nil)
    case "seek":
      if let p = player, let s = args["seconds"] as? Double { p.currentTime = max(0, min(s, p.duration)) }
      result(nil)
    case "position":
      guard let p = player else { return result(nil) }
      result(["position": p.currentTime, "duration": p.duration, "playing": p.isPlaying])
    case "unload":
      unload()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// No Now Playing information, and no lock-screen controls that would make the app the "now
  /// playing" one: a blessing's title or words must never show on a locked phone.
  private static func hideFromLockScreen() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    let c = MPRemoteCommandCenter.shared()
    for command in [c.playCommand, c.pauseCommand, c.togglePlayPauseCommand, c.stopCommand,
                    c.skipBackwardCommand, c.skipForwardCommand, c.changePlaybackPositionCommand,
                    c.nextTrackCommand, c.previousTrackCommand] {
      command.removeTarget(nil)
      command.isEnabled = false
    }
  }

  private static func unload() {
    guard let p = player else { return }
    p.stop()
    player = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  final class Delegate: NSObject, AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
      let end = p.duration
      DispatchQueue.main.async {
        channel?.invokeMethod("stopped", arguments: ["position": end])
      }
    }
  }
}
