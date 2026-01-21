//
//  ContentView.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 2/28/25.
//

import SwiftUI
import CoreBluetooth

class BluetoothViewModel:NSObject, ObservableObject{
    private var centralManager:CBCentralManager?
    private var peripherals: [CBPeripheral]=[]
    @Published var peripheralNames:[String]=[]
    override init(){
        super.init()
        self.centralManager=CBCentralManager(delegate: self , queue: .main)
    }
}

extension BluetoothViewModel: CBCentralManagerDelegate{
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn{
            self.centralManager?.scanForPeripherals(withServices: nil)
        }
    }
    func searchForDevices(){
        self.centralManager?.scanForPeripherals(withServices: nil)
    }
    func centralManager(_ central : CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String:Any],rssi RSSI :NSNumber){
        if !peripherals.contains(peripheral){
            self.peripherals.append(peripheral)
            self.peripheralNames.append(peripheral.name ?? "Unnamed Device. Identifier: \(peripheral.identifier)")
        }
    }
}

struct ContentView: View {
    var bgColors:[Color]=[.BG_1,.BG_2]
    
    var body: some View {
        
        TabView{
            
            Tab("My Watch",systemImage:"watch.analog"){
                WatchScreen()
                
            }
            /*
            Tab("Apps",systemImage:"appclip"){
                LockedWebView().edgesIgnoringSafeArea(.bottom)

                
            }
             */
            Tab("Watch Settings",systemImage:"gearshape"){
                WatchSettingsScreen()
            }
            .badge("1")
            
        }
        .edgesIgnoringSafeArea(.bottom)
        
        .onAppear() {
            let standardAppearance = UITabBarAppearance()
            standardAppearance.shadowColor = UIColor(Color.blue)
            
            
            
            UITabBar.appearance().standardAppearance = standardAppearance
        }
        
        
        
        
    }
    
   
        
}

struct DevicesAvailableView:View{
    @ObservedObject private var bluetoothViewModel=BluetoothViewModel()

    var body: some View{
        NavigationView{
            List(bluetoothViewModel.peripheralNames,id: \.self){ peripheral in
                NavigationLink(peripheral){
                    VStack {
                        Text(peripheral)
                            .font(.title)
                            .fontWeight(.bold)
                            .padding()
                        
                        
                        Button("Connect"){
                            //  CBCentralManager.connect(peripheral)
                        }
                    }
                }
                
            }
            .navigationTitle("Devices")
        }
        .refreshable {
            bluetoothViewModel.searchForDevices()
        }
    }
}




#Preview {
    ContentView()
}

