import Foundation
import HealthKit

class CommandInterpreter {

    public static let shared = CommandInterpreter()

    public var ble: BLEManager?

    private let findPhoneAlarm = FindPhoneAlarm()

    @MainActor
    public func handleCommand(command: String) {
        logger.log(
            "[CommandInterpreter] received: '\(command, privacy: .public)' len=\(command.count, privacy: .public)"
        )

        switch command {
        case "Start Polling GPS":
            LocationManager.shared.startGPSForwarding()

        case "Stop Polling GPS":
            LocationManager.shared.stopGPSForwarding()

        case "FindPhone":
            findPhoneAlarm.start()

        case "StopFindPhone":
            findPhoneAlarm.stop()
        case "Request Time":
            DataSendManager.sendCurrentTime()

        case "Pinging Connection...":
            logger.log("[CommandInterpreter] Responding to connection ping")
            ble?.send("iPhone Connected")

        case "Request Weather":
            if Settings.shared.pushWeather {
                DataSendManager.sendCurrentWeather()

            } else {
                logger.log("[WEATHER] pushWeather DISABLED — ignoring request")
            }

        case "Request Location":
            if Settings.shared.pushLocation {
                DataSendManager.sendCurrentLocation()
            }

        default:
            break
        }
    }
    
    func handleJSON(_ j: [String: Any]) {
        logger.log("Got json")

        switch j["type"] as? String {
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

/*
 Taken from espruinoAppLoaderCore
 setTime : () => {
     /* connect FIRST, then work out the time - otherwise
     we end up with a delay dependent on how long it took
     to open the device chooser. */
     return Comms.write(" \x08").then(() => { // send space+backspace (eg no-op)
       let d = new Date();
       let tz = d.getTimezoneOffset()/-60
       let cmd = '\x10setTime('+(d.getTime()/1000)+');';
       // in 1v93 we have timezones too
       cmd += 'E.setTimeZone('+tz+');';
       cmd += "(s=>s&&(s.timezone="+tz+",require('Storage').write('setting.json',s)))(require('Storage').readJSON('setting.json',1))\n";
       return Comms.write(cmd);
     });
   },
 */
struct WatchTimePacket: Codable {
    let id: String
    let tz:Double
    let time:Double
}
