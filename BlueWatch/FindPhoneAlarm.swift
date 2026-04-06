// FindPhoneAlarm.swift

import AVFoundation
import Foundation
import UIKit
import MediaPlayer  // for MPVolumeView / system volume override

class FindPhoneAlarm: NSObject, AVAudioPlayerDelegate {
    private var audioPlayer: AVAudioPlayer?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    // We temporarily crank system volume to max, then restore it when done.
    private var originalVolume: Float = 0.5

    public var isActive: Bool {
        audioPlayer?.isPlaying ?? false
    }

    func start() {
        guard !isActive else { return }

        // ── Background task ───────────────────────────────────────────────────
        // Gives us time to set up the audio session even if the screen locks
        // the instant the command arrives from the watch.
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.stop()
        }

        // ── Audio session ─────────────────────────────────────────────────────
        // .playback: continues in background, ignores the Silent/Ringer switch.
        // NOT .duckOthers — we want full volume, not ducked underneath something.
        // NOT .mixWithOthers — we want exclusive audio so we're as loud as possible.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.overrideOutputAudioPort(.speaker)  // use bottom speaker
            try session.setActive(true)
        } catch {
            print("[FindPhone] Audio session setup failed: \(error)")
            endBackgroundTask()
            return
        }

        // ── Override system volume to maximum ─────────────────────────────────
        // AVAudioPlayer.volume is relative to system volume — if the phone is
        // at 10% volume, even volume=1.0 is quiet. We temporarily set system
        // volume to 1.0 so the alarm is always at max hardware output.
        //
        // MPMusicPlayerController.applicationMusicPlayer.volume is deprecated
        // but still works. The correct modern way is AVAudioSession, but that
        // only controls input gain, not output volume. The hack below is the
        // only way to programmatically set output volume on iOS without a
        // private API. It uses a hidden MPVolumeView slider.
        originalVolume = AVAudioSession.sharedInstance().outputVolume
        setSystemVolume(1.0)

        // ── Load and play ─────────────────────────────────────────────────────
        guard let url = Bundle.main.url(forResource: "findphone", withExtension: "wav") else {
            print("[FindPhone] Sound file 'findphone.wav' not found in bundle")
            endBackgroundTask()
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate     = self
            audioPlayer?.volume       = 1.0
            audioPlayer?.numberOfLoops = -1  // loop forever until stop() is called
            audioPlayer?.prepareToPlay()

            let started = audioPlayer?.play() ?? false
            if started {
                print("[FindPhone] Alarm started")
            } else {
                print("[FindPhone] play() returned false — audio session may not be ready")
                endBackgroundTask()
            }
        } catch {
            print("[FindPhone] Player init failed: \(error)")
            endBackgroundTask()
        }
    }

    func stop() {
        guard isActive else { return }

        audioPlayer?.stop()
        audioPlayer = nil

        // Restore system volume to what it was before
        setSystemVolume(originalVolume)

        // Deactivate session so music/podcasts can resume
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )

        endBackgroundTask()
        print("[FindPhone] Alarm stopped")
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Only fires if numberOfLoops is not -1. Safe to have for completeness.
        stop()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("[FindPhone] Decode error: \(error?.localizedDescription ?? "unknown")")
        stop()
    }

    // MARK: - Private helpers

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    /// The only reliable way to set output volume programmatically on iOS.
    /// Creates a hidden MPVolumeView and moves its slider — this is what
    /// apps like alarm clocks do. Requires MediaPlayer framework.
    private func setSystemVolume(_ volume: Float) {
        // MPVolumeView must be added to a visible window to work.
        // We add it off-screen (frame outside visible area).
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first else { return }

        let volumeView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        window.addSubview(volumeView)

        // Find the volume slider inside MPVolumeView and set it
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            if let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first {
                slider.value = volume
            }
            volumeView.removeFromSuperview()
        }
    }
}
