//
//  WatchSenders.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 10/4/26.
//

import Foundation


class DataSendManager{
    
    static func sendCurrentTime(){
        let watchTimePacket:WatchTimePacket = WatchTimePacket(
            id: "Time",
            tz: Double(TimeZone.current.secondsFromGMT()) / 3600.0,
            time:Date().timeIntervalSince1970
        )
        let ble = BLEManager.shared
        ble.sendJSON(data: watchTimePacket)
    }
    
    static func sendCurrentWeather(){
        Task{
            await WeatherManager.shared.updateWeatherAndSend()
        }
    }
    
    static func sendCurrentLocation(){
        Task{
            await LocationManager.shared.sendLocation()
        }
    }
}


