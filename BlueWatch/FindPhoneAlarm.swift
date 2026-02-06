import AVFAudio
import Foundation
import UIKit // Required for UIBackgroundTaskIdentifier

class FindPhoneAlarm: NSObject, AVAudioPlayerDelegate {
    private var audioPlayer: AVAudioPlayer?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    public var isActive: Bool {
        return audioPlayer?.isPlaying ?? false
    }

    func start() {
        // 1. Begin a Background Task to ensure the setup code finishes
        //    even if the user locks the phone immediately.
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }

        // 2. Configure Audio Session
        do {
            let session = AVAudioSession.sharedInstance()
            
            // .playback is required to play in background and ignore the Silent Switch
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            
            // Force audio to the bottom loudspeaker (Louder)
            try session.overrideOutputAudioPort(.speaker)
            
            try session.setActive(true)
        } catch {
            print("Audio Session Setup Failed: \(error)")
            endBackgroundTask()
            return
        }

        // 3. Setup Player
        guard let url = Bundle.main.url(forResource: "findphone", withExtension: "wav") else {
            print("Sound file not found")
            endBackgroundTask()
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            
            // Set player volume to 100% (relative to system volume)
            audioPlayer?.volume = 1.0
            
            // Loop indefinitely (-1) or a specific number of times
            audioPlayer?.numberOfLoops = -1
            
            audioPlayer?.prepareToPlay()
            let success = (audioPlayer?.play())!
            
            if success {
                print("Failed to start playback")
                endBackgroundTask()
            }
        } catch {
            print("Player Init Failed: \(error)")
            endBackgroundTask()
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        
        // Deactivate session to allow other apps to resume audio
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        
        endBackgroundTask()
        print("FindPhoneAlarm stopped")
    }

    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
}
