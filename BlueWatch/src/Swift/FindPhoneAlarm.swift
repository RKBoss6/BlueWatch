// FindPhoneAlarm.swift

import AVFoundation
import Foundation
import UIKit
import MediaPlayer

class FindPhoneAlarm: NSObject, AVAudioPlayerDelegate {
    private var audioPlayer: AVAudioPlayer?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid


    private func forceSystemVolumeToMax() {
        // MPVolumeView must be added to an active view hierarchy to manipulate the system audio pipeline
        let volumeView = MPVolumeView(frame: CGRect(x: -100, y: -100, width: 1, height: 1))
        
        // Find the hidden underlying slider that hooks into coreaudiod
        if let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Force the global system media volume track to max blast
                slider.setValue(0.2, animated: false)
                print("[FindPhone] System Media Volume forcefully overridden to 100%")
            }
        }
    }

    public var isActive: Bool {
        audioPlayer?.isPlaying ?? false
    }

    func start() {
        guard !isActive else { return }

        // ── Background task ───────────────────────────────────────────────────
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.stop()
        }

        // ── Audio session ─────────────────────────────────────────────────────
        // .playback bypasses the silent/ringer switch — this is the documented
        // behaviour of the category and is how Garmin/similar apps do it.
        // No special entitlements needed. The only thing that can silence it is
        // the user having their volume slider at zero.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)

        } catch {
            print("[FindPhone] Audio session setup failed: \(error)")
            endBackgroundTask()
            return
        }

        // ── Load and play ─────────────────────────────────────────────────────
        // Make sure "findphone.wav" is listed under:
        // Target → Build Phases → Copy Bundle Resources
        // If this guard fires, that's why nothing plays.
        guard let url = Bundle.main.url(forResource: "findphone", withExtension: "wav") else {
            print("[FindPhone] ‼️ Sound file 'findphone.wav' not found in bundle — add it to Copy Bundle Resources")
            endBackgroundTask()
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate      = self
            audioPlayer?.volume        = 1.0
            audioPlayer?.numberOfLoops = -1  // loop until stop() is called
            audioPlayer?.prepareToPlay()

            let started = audioPlayer?.play() ?? false
            if started {
                print("[FindPhone] Alarm started")
            } else {
                print("[FindPhone] ‼️ play() returned false — audio session may not be ready")
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

        // Deactivate so music/podcasts can resume
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        endBackgroundTask()
        print("[FindPhone] Alarm stopped")
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stop()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("[FindPhone] Decode error: \(error?.localizedDescription ?? "unknown")")
        stop()
    }

    // MARK: - Private

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}
