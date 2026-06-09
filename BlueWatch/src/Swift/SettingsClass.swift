//
//  SettingsState.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 4/6/26.
//

import Foundation

public class Settings{
    public static var instance:Settings = Settings()
    
    private var webURLKey:String="webURL"
    public var webURL:String{
        didSet{
            LocalStorage.set(webURL, forKey: webURLKey)
        }
    }
    
    private var enableHScrollKey:String="enableHScroll"
    public var enableHScroll:Bool{
        didSet{
            LocalStorage.set(enableHScroll, forKey: enableHScrollKey)
        }
    }
    
    private var enableVScrollKey:String="enableVScroll"
    public var enableVScroll:Bool{
        didSet{
            LocalStorage.set(enableVScroll, forKey: enableVScrollKey)
        }
    }
    
    private var autoConnectKey:String="autoConnect"
    public var autoConnect:Bool{
        didSet{
            LocalStorage.set(autoConnect, forKey: autoConnectKey)
        }
    }
    
    private var pushWeatherKey:String="pushWeather"
    public var pushWeather:Bool{
        didSet{
            LocalStorage.set(pushWeather, forKey: pushWeatherKey)
        }
    }
    
    private var pushLocationKey:String="pushLocation"
    public var pushLocation:Bool{
        didSet{
            LocalStorage.set(pushLocation, forKey: pushLocationKey)
        }
    }
    
    private var lowBattNotifyKey:String="lowBattNotify"
    public var lowBattNotify:Bool{
        didSet{
            LocalStorage.set(lowBattNotify, forKey: lowBattNotifyKey)
        }
    }
    
    
    
    init(){
        // load, or use defaults
        webURL=LocalStorage.getString(forKey: webURLKey) ?? "banglejs.com/apps"
        enableHScroll=LocalStorage.getBool(forKey: enableHScrollKey) ?? false
        enableVScroll=LocalStorage.getBool(forKey: enableVScrollKey) ?? true
        autoConnect=LocalStorage.getBool(forKey: autoConnectKey) ?? true
        pushWeather=LocalStorage.getBool(forKey: pushWeatherKey) ?? true
        pushLocation=LocalStorage.getBool(forKey: pushLocationKey) ?? true
        lowBattNotify=LocalStorage.getBool(forKey: lowBattNotifyKey) ?? false
    }
}
