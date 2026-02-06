import Foundation
import SwiftUI
public struct DeviceInfo{
    var supportsWeather:Bool
    var supportsLocation:Bool
    var displayName:String
    var manufacturerName:String
    var logo:Image?
    var autoConnect:Bool
    var deviceSupportClass:DeviceBase?
}
