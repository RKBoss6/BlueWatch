//
//  SettingsState.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 4/6/26.
//

import Foundation

public class Settings:ObservableObject{
    public static var shared:Settings = Settings()
    
    private var webURLKey:String="webURL"
    @Published public var webURL:String{
        didSet{
            LocalStorage.set(webURL, forKey: webURLKey)
        }
    }
    
    private var deviceNameKey:String="deviceName"
    @Published public var deviceName:String{
        didSet{
            LocalStorage.set(deviceName, forKey: deviceNameKey)
        }
    }
    
    private var optimizedBtChunksKey:String="optimizedBtChunks"
    @Published public var optimizedBtChunks:Bool{
        didSet{
            LocalStorage.set(deviceName, forKey: deviceNameKey)
        }
    }
    
    private var enableHScrollKey:String="enableHScroll"
    @Published public var enableHScroll:Bool{
        didSet{
            LocalStorage.set(enableHScroll, forKey: enableHScrollKey)
        }
    }
    
    private var enableVScrollKey:String="enableVScroll"
    @Published public var enableVScroll:Bool{
        didSet{
            LocalStorage.set(enableVScroll, forKey: enableVScrollKey)
        }
    }
    
    private var autoConnectKey:String="autoConnect"
    @Published public var autoConnect:Bool{
        didSet{
            LocalStorage.set(autoConnect, forKey: autoConnectKey)
        }
    }
    
    private var pushWeatherKey:String="pushWeather"
    @Published public var pushWeather:Bool{
        didSet{
            LocalStorage.set(pushWeather, forKey: pushWeatherKey)
        }
    }
    
    private var pushLocationKey:String="pushLocation"
    @Published public var pushLocation:Bool{
        didSet{
            LocalStorage.set(pushLocation, forKey: pushLocationKey)
        }
    }
    
    private var sendToHealthKitKey:String="sendToHealthKit"
    @Published public var sendToHealthKit:Bool{
        didSet{
            LocalStorage.set(sendToHealthKit, forKey: sendToHealthKitKey)
        }
    }
    
    private var showFindPhoneNotificationKey:String="showFindPhoneNotification"
    @Published public var showFindPhoneNotification:Bool{
        didSet{
            LocalStorage.set(showFindPhoneNotification, forKey: showFindPhoneNotificationKey)
        }
    }
    
    private var lowBattNotifyKey:String="lowBattNotify"
    @Published public var lowBattNotify:Bool{
        didSet{
            LocalStorage.set(lowBattNotify, forKey: lowBattNotifyKey)
        }
    }
    
    private var weatherRateLimitKey:String="weatherRateLimit"
    @Published public var weatherRateLimit:Int{
        didSet{
            LocalStorage.set(weatherRateLimit, forKey: weatherRateLimitKey)
        }
    }
    private var locationRateLimitKey:String="locationRateLimit"
    @Published public var locationRateLimit:Int{
        didSet{
            LocalStorage.set(locationRateLimit, forKey: locationRateLimitKey)
        }
    }
    
    
    
    init(){
        //register defaults
        UserDefaults.standard.register(defaults: [
            webURLKey: "banglejs.com/apps",
            enableHScrollKey: false,
            showFindPhoneNotificationKey:true,
            enableVScrollKey: true,
            autoConnectKey: true,
            pushWeatherKey: true,
            pushLocationKey: true,
            lowBattNotifyKey: false,
            sendToHealthKitKey: true,
            optimizedBtChunksKey: true,
            deviceNameKey: ViewModel.shared.savedDevice,
            weatherRateLimitKey: 10
        ])
        // load
        webURL=LocalStorage.getString(forKey: webURLKey) ?? "banglejs.com/apps"
        enableHScroll=LocalStorage.getBool(forKey: enableHScrollKey) ?? false
        enableVScroll=LocalStorage.getBool(forKey: enableVScrollKey) ?? true
        autoConnect=LocalStorage.getBool(forKey: autoConnectKey) ?? true
        pushWeather=LocalStorage.getBool(forKey: pushWeatherKey) ?? true
        pushLocation=LocalStorage.getBool(forKey: pushLocationKey) ?? true
        lowBattNotify=LocalStorage.getBool(forKey: lowBattNotifyKey) ?? false
        sendToHealthKit=LocalStorage.getBool(forKey: sendToHealthKitKey) ?? true
        showFindPhoneNotification=LocalStorage.getBool(forKey: showFindPhoneNotificationKey) ?? true
        deviceName=LocalStorage.getString(forKey: deviceNameKey) ?? ViewModel.shared.savedDevice
        weatherRateLimit=Int(LocalStorage.getNumber(forKey: weatherRateLimitKey) ?? 10)
        locationRateLimit=Int(LocalStorage.getNumber(forKey: locationRateLimitKey) ?? 10)
        optimizedBtChunks=LocalStorage.getBool(forKey: optimizedBtChunksKey) ?? true
    }
}
