import AVFAudio
import Foundation
class FindPhoneAlarm {
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private var vibrationTimer: Timer?

    public var isActive: Bool { timer != nil }

    private var playCount = 0
    private let maxPlays = 5

    func start() {
        guard !isActive else { return }

        print("Starting FindPhoneAlarm")

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

        } catch {
            print("Audio session setup failed:", error)
            return
        }

        guard let url = Bundle.main.url(forResource: "findphone", withExtension: "wav") else {
            print("Sound file not found")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.volume = 1.0
            audioPlayer?.prepareToPlay()
        } catch {
            print("Failed to create audio player:", error)
            return
        }

        playCount = 0
        scheduleNextPlay()
    }

    private func scheduleNextPlay() {
        guard playCount < maxPlays else {
            stop()
            return
        }

        playCount += 1
        audioPlayer?.play()

        // Vibrate in sync with the sound
        startVibratingRhythmically()

        guard let duration = audioPlayer?.duration else { return }

        timer = Timer.scheduledTimer(withTimeInterval: duration + 0.2, repeats: false) { [weak self] _ in
            self?.scheduleNextPlay()
        }
    }

    private func startVibratingRhythmically() {
        // Invalidate any old vibration timer
        vibrationTimer?.invalidate()

        guard let duration = audioPlayer?.duration else { return }

        // Example: vibrate every 0.3s during the sound
        let interval = 0.3
        var elapsed: TimeInterval = 0

        vibrationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] t in
            guard let self = self else { return }

            // Fire vibration
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

            elapsed += interval
            if elapsed >= duration {
                t.invalidate()  // Stop vibrating when sound ends
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil

        vibrationTimer?.invalidate()
        vibrationTimer = nil

        audioPlayer?.stop()
        audioPlayer = nil
        playCount = 0

        try? AVAudioSession.sharedInstance().setActive(false)
        print("FindPhoneAlarm stopped")
    }
}

