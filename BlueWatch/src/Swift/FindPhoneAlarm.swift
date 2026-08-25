// FindPhoneAlarm.swift

import AVFoundation
import Foundation
import UIKit
import MediaPlayer
import CoreHaptics
import AudioToolbox

class FindPhoneAlarm: NSObject, AVAudioPlayerDelegate {
    private var audioPlayer: AVAudioPlayer?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid


    public var isActive: Bool {
        audioPlayer?.isPlaying ?? false
    }

   


    

    // Global references to manage execution states
    var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    var masterCycleTimer: Timer?
    var rapidFireTimer: Timer?
    private var currentSystemVolume: Float = 0.5
    private let volumeView = MPVolumeView(frame: .zero)
    private var originalVolume: Float?
    private func setSystemVolume(_ volume: Float) {
        
        let slider = volumeView.subviews.first { $0 is UISlider } as? UISlider
        slider?.setValue(max(0.0, min(volume, 1.0)), animated: false)
    }
    override init() {
        super.init()
        let session = AVAudioSession.sharedInstance()
        currentSystemVolume = session.outputVolume
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AVAudioSessionSystemVolumeDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, !self.isActive, self.originalVolume == nil else { return }
            if let volume = notification.userInfo?["AVAudioSessionVolumeParameter"] as? Float {
                self.currentSystemVolume = volume
            }
        }
    }
    /// Starts the true 3-second continuous hardware buzz followed by a 1-second pause
    func startMaxVibration() {
        stopVibration()
        
        // 1. Force the audio session to stay awake in the background
        configureBackgroundAudioSession()
        
        // 2. Request a background execution assertion from iOS
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "MaxVibrationTask") {
            self.stopVibration()
        }
        
        // 3. Immediately run the first cycle
        runThreeSecondBuzzCycle()
        
        // 4. Repeat the entire master cycle every 4 seconds (3s buzz + 1s pause)
        masterCycleTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            self.runThreeSecondBuzzCycle()
        }
    }

    /// Helper that handles the rapid-fire burst for exactly 3 seconds
    private func runThreeSecondBuzzCycle() {
        // Stop any lingering rapid-fire timers from previous cycles
        rapidFireTimer?.invalidate()
        
        // Start rapid-firing max voltage commands every 50 milliseconds
        rapidFireTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            // SystemSoundID 4095 is a raw hardware alert that forces a heavy haptic click
            AudioServicesPlaySystemSound(4095)
        }
        
        // Automatically kill the rapid-fire timer after 3.0 seconds to create the 1-second pause
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.rapidFireTimer?.invalidate()
            self.rapidFireTimer = nil
        }
    }

    /// Configures the audio subsystem to override silent switches and background suspension
    private func configureBackgroundAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            logger.log("Audio configuration failure: \(error)")
        }
    }

    /// Halts all loops instantly and releases system execution flags
    func stopVibration() {
        rapidFireTimer?.invalidate()
        rapidFireTimer = nil
        
        masterCycleTimer?.invalidate()
        masterCycleTimer = nil
        
        if backgroundTaskIdentifier != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            backgroundTaskIdentifier = .invalid
        }
    }




    
    func start() {
        guard !isActive else { return }

        // 1. Capture original system volume FIRST before altering any audio settings
        let session = AVAudioSession.sharedInstance()
        if originalVolume == nil {
            originalVolume = currentSystemVolume
        }
        print("FIND PHONE: saved volume: \(originalVolume ?? -1)")

        // 2. Start vibration and audio session configuration
        startMaxVibration()
        
        do {
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
            
            // 3. Maximize volume after capturing original volume
            setSystemVolume(1.0)
        } catch {
            logger.log("[FindPhone] Audio session setup failed: \(error)")
            endBackgroundTask()
            return
        }

        guard let url = Bundle.main.url(forResource: "findphone", withExtension: "wav") else {
            logger.log("[FindPhone] Sound file 'findphone.wav' not found in bundle")
            endBackgroundTask()
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate      = self
            audioPlayer?.volume        = 1.0
            audioPlayer?.numberOfLoops = 3
            audioPlayer?.prepareToPlay()

            let started = audioPlayer?.play() ?? false
            if started {
                logger.log("[FindPhone] Alarm started")
            } else {
                logger.log("[FindPhone] play() returned false")
                endBackgroundTask()
            }
        } catch {
            logger.log("[FindPhone] Player init failed: \(error)")
            endBackgroundTask()
        }
    }

    func stop() {
        guard isActive else { return }
        
        if Settings.shared.showFindPhoneNotification {
            showNotification()
        }
        
        stopVibration()
        audioPlayer?.stop()
        audioPlayer = nil

        // 1. Restore the original system volume while the audio session is still active
        let targetRestoreVolume = originalVolume ?? currentSystemVolume
        setSystemVolume(targetRestoreVolume)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            self.originalVolume = nil
            self.endBackgroundTask()
        }
       

        logger.log("[FindPhone] Alarm stopped")
        BLEManager.shared.send("FindPhone Stopped")
    }
    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stop()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        logger.log("[FindPhone] Decode error: \(error?.localizedDescription ?? "unknown")")
        stop()
    }

    func showNotification(){
        Utils.pushNotification(title: "Find Phone", body: "Find phone triggered from watch." , id: "FindPhoneConfirm")

    }
    // MARK: - Private

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}
