import Foundation
import SwiftUI

struct BangleJS2: Device {
    
    
    let supportsWeatherPushing = true
    
    let supportsLocationPushing =  true
    
    let displayName = "Bangle.js 2"
    
    let manufacturerName = "Espruino"
    
    let thumbnail:Image = Image("")
    
    

    func onConnect() {}
    func onDisconnect() {}
}

