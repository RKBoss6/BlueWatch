import Foundation
import HealthKit

class CommandInterpreter {
    
    public static let shared = CommandInterpreter()

    public var ble: BLEManager?

    private let findPhoneAlarm = FindPhoneAlarm()
    
    
    @MainActor
    public func handleCommand(command: String) {
        logger.log("[CommandInterpreter] received: '\(command, privacy: .public)' len=\(command.count, privacy: .public)")
        
        switch command {
        case "Start Polling GPS":
            LocationManager.shared.startGPSForwarding()
            
        case "Stop Polling GPS":
            LocationManager.shared.stopGPSForwarding()
            
        case "FindPhone":
            findPhoneAlarm.start()
            
        case "StopFindPhone":
            findPhoneAlarm.stop()
            
        case "Pinging Connection...":
            logger.log("[CommandInterpreter] Responding to connection ping")
            ble?.send("iPhone Connected")
            
        case "Request Weather":
            logger.log("[WEATHER] Request Weather received")
            
            if Settings.shared.pushWeather {
                logger.log("[WEATHER] pushWeather enabled — starting weather task")
                
                Task {
                    logger.log("[WEATHER] Starting updateWeatherAndSend()")
                    await WeatherManager.shared.updateWeatherAndSend()
                    logger.log("[WEATHER] updateWeatherAndSend() returned")
                }
            } else {
                logger.log("[WEATHER] pushWeather DISABLED — ignoring request")
            }
            
        case "Request Location":
            if Settings.shared.pushLocation {
                Task {
                    await LocationManager.shared.sendLocation()
                }
            }
            
        default:
            break
        }
    }
    
    func handleJSON(_ j: [String: Any]) {
        logger.log("Got json")
        
        switch (j["type"] as? String) {
        case "health":
            HealthManager.shared.handleHealthData(j)
            
        case "systemInfo":
            logger.log("Got system json")
            handleSystemInfo(j)
            
        default:
            break
        }
    }
    
    func handleSystemInfo(_ data: [String: Any]) {
        if let batt = data["batt"] as? Double {
            logger.log("Got battery \(String(batt))")
            
            DataService.addDataPointInBackground(
                timestamp: Date(),
                value: batt,
                type: .battery,
                alwaysSave: false
            )
            
            DispatchQueue.main.async {
                LocalData.shared.battery = String(Int(batt))
                logger.log("batt updated")
            }
            
            if batt < 80 && Settings.shared.lowBattNotify {
                Utils.pushNotification(
                    title: "Bangle.js",
                    body: "Battery below 15%. Charge soon!",
                    id: "LowBatt"
                )
            }
        }
    }
}
