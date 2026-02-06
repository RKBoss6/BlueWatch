//
//  BangleJsDeviceClass.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 1/21/26.
//

import Foundation



public class BangleJsDeviceClass:DeviceBase {
    // Define all device info here.
    public lazy var deviceInfo: DeviceInfo = {
        DeviceInfo(
            supportsWeather: true,
            supportsLocation: true,
            displayName: "Bangle.js",
            manufacturerName: "Espruino",
            logo: nil,
            autoConnect: true,
            deviceSupportClass: self
        )
    }()

    public override init() {
        
        super.init()
    }
}

