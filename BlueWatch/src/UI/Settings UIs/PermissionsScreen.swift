//
//  PermissionsScreen.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 8/9/26.
//

import SwiftUI
struct PermissionsScreen :View {
    var hasNotifications = 
    var body: some View{
        VStack{
            Spacer()
            Section{
                VStack(spacing: 16) {
                        Text("Has Health Permissions")
                            .frame(maxWidth:.infinity)
                    
                
                }
                .padding()
                .liquidGlass(cornerRadius: 24, backgroundColor: BlueWatchApp.hasHealthKitPermissions() ? .green : .red)

                .ignoresSafeArea(.all)
                .listRowInsets(EdgeInsets())
                
            
            }
            .listRowBackground(Color.clear)
            .padding(.leading)
            .padding(.trailing)

            Section{
                VStack(spacing: 16) {
                        Text("Has Notification Permissions")
                            .frame(maxWidth:.infinity)
                    
                
                }
                .padding()
                .liquidGlass(cornerRadius: 24, backgroundColor: BlueWatchApp.checkNotificationPermissions() ? .green : .red)

                .ignoresSafeArea(.all)
                .listRowInsets(EdgeInsets())
                
            
            }
            .listRowBackground(Color.clear)
            .padding(.leading)
            .padding(.trailing)
            Section{
                VStack(spacing: 16) {
                        Text("Has Health Permissions")
                            .frame(maxWidth:.infinity)
                    
                
                }
                .padding()
                .liquidGlass(cornerRadius: 24, backgroundColor: .red)

                .ignoresSafeArea(.all)
                .listRowInsets(EdgeInsets())
                
            
            }
            .listRowBackground(Color.clear)
            .padding(.leading)
            .padding(.trailing)
            Section{
                VStack(spacing: 16) {
                    Button{
                        BlueWatchApp.requestHealthAuthorization()

                    }label:{
                        Text("Request Health Permissions")
                    }
                    Divider()
                    Button{
                        Task{
                            await BlueWatchApp.requestNotificationAuthorization()
                        }
                    }label:{
                        Text("Request Notification Permissions")
                    }
                    Divider()
                    Button{
                        LocationManager.shared.requestAuthorization()
                    }label:{
                        Text("Request Location Permissions")
                    }
                    
                    
                    
                    
                    
                }
                .padding()
                .liquidGlass(cornerRadius: 24)
                .ignoresSafeArea(.all)
                .listRowInsets(EdgeInsets())
                
            
            } footer:{
                Text("If you've already accepted permissions, no pop-up will show.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
            .listRowBackground(Color.clear)
            .padding()
            Spacer()
        }
        .appBackground()
        .navigationTitle("App Permissions")
    }
        
}

#Preview{
    PermissionsScreen()
}
