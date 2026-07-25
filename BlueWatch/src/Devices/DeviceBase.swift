//
//  BangleJsDeviceClass.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 1/21/26.
//

import Foundation
import SwiftUI

protocol Device {
    var supportsWeatherPushing: Bool { get }
    var supportsLocationPushing: Bool { get }
    var displayName: String { get }
    var manufacturerName: String { get }
    var thumbnail: Image { get }
    func onConnect()
    func onDisconnect()
}

