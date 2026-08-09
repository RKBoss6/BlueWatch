//
//  MoreScreen.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 8/9/26.
//

import SwiftUI

#warning("Make sure you change the BlueWatch bangle.js version before upload!!!")
struct MoreScreen: View {
    @Environment(\.openURL) var openURL
    @StateObject var settings: Settings = Settings.instance
    @State var temp:Bool=false
    var vm:ViewModel=ViewModel.instance
    var body: some View {
        VStack{
            HStack {

                Text(settings.deviceName.isEmpty==false ? settings.deviceName : vm.savedDevice)
                    .font(.title)
                    .fontWeight(.bold)
                
               
            }.padding()
            Spacer()
            
            Image(vm.savedDevice=="Bangle.js 2" ? "BangleJS2" : "BangleJS1" )
                .resizable()
                .frame(width: 240,height: 240)
            
            Spacer()
            VStack{
                Section(){
                    VStack(spacing: 16) {
                        
                        Button {
                            if let url = URL(string: "https://github.com/RKBoss6/BlueWatch") {
                                openURL(url)
                            }
                            
                        } label:{
                            HStack{
                                Text("BlueWatch is open source!")
                                    .frame(maxWidth:.infinity, alignment: .leading)
                                    .tint(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .tint(.primary)
                            }
                        }
                        Divider()
                        Button {
                            if let url = URL(string: "https://github.com/RKBoss6/BlueWatch/issues/new") {
                                openURL(url)
                            }
                            
                        } label:{
                            HStack{
                                Text("Report an issue or suggest new features")
                                    .frame(maxWidth:.infinity, alignment: .leading)
                                    .tint(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .tint(.primary)
                            }
                        }
                        
                        
                        
                        
                    }
                    .padding()
                    .liquidGlass(cornerRadius: 24)
                    .frame(width:.infinity,height: .infinity)
                    .ignoresSafeArea(.all)
                    .listRowInsets(EdgeInsets())
                }
                
                .listRowBackground(Color.clear)
                Section {
                    HStack {
                        Text("Needs Bangle.js BlueWatch version:")
                        Spacer()
                        Text("v0.03")
                            .bold()
                    }
                    
                }
                .padding()
                .liquidGlass(cornerRadius: 24)
                .ignoresSafeArea(.all)
                .listRowInsets(EdgeInsets())
                .padding(.top, 10)
                Section {
                    VStack(spacing: 16) {
                        
                        NavigationLink(destination: PermissionsScreen()){
                            HStack {
                                Image(systemName: "person.badge.key")
                                Text("App Permissions")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .foregroundStyle(.primary)
                        Divider()
                        NavigationLink(destination: WatchSettingsScreen()) {
                            HStack {
                                Image(systemName: "gear")
                                Text("Settings")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .foregroundStyle(.primary)
                        
                    }
                    .padding()
                    .liquidGlass(cornerRadius: 24)
                    .ignoresSafeArea(.all)
                    .listRowInsets(EdgeInsets())
                }
                .padding(.top, 12)
            }.padding()
                .padding(.bottom,20)
                .listRowBackground(Color.clear)
        }
        .appBackground()
    }
}


#Preview {
    MoreScreen()
}
