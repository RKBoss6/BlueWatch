//
//  ViewModel.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 4/6/26.
//

import Foundation

public class ViewModel: ObservableObject {
    @Published var webReloadTrigger = UUID()
    static var instance:ViewModel = ViewModel()
    func requestWebReload() {
        webReloadTrigger = UUID() // Change value to trigger update
    }
}
