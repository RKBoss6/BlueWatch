//
//  ViewModel.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 4/6/26.
//

import Foundation

public class ViewModel: ObservableObject {
    @Published var webReloadTrigger = UUID()
    public static var instance:ViewModel = ViewModel()
    var savedDevice:String{
        set{
            LocalStorage.set(newValue, forKey: "savedDevice")
        }
        get{
            LocalStorage.getString(forKey: "savedDevice") ?? ""
        }
    }
    func requestWebReload() {
        webReloadTrigger = UUID() // Change value to trigger update
    }
    
}
