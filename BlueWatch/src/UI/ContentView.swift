//
//  ContentView.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 2/28/25.
//

import SwiftUI
import CoreBluetooth


struct ContentView: View {
    @State private var vm: ViewModel = ViewModel.shared
    
    var body: some View {
        NavigationStack{
            if vm.savedDevice == "" {
                WelcomeScreen()
            } else {
                
                    TabView{
                        
                        Tab("My Watch",systemImage:"watch.analog"){
                            WatchScreen()
                                .edgesIgnoringSafeArea(.bottom)
                            
                        }
                        
                        Tab("Apps",systemImage:"app.shadow"){
                            WebView().edgesIgnoringSafeArea(.bottom)
                            
                            
                        }
                        
                        Tab("More",systemImage:"ellipsis"){
                            MoreScreen()
                        }
                        //.badge("1")
                        
                    }
                    .edgesIgnoringSafeArea(.bottom)
                    
                    .onAppear() {
                        
                        let standardAppearance = UITabBarAppearance()
                        standardAppearance.shadowColor = UIColor(Color.blue)
                        UITabBar.appearance().standardAppearance = standardAppearance
                        // start connection
                        BLEManager.shared.start()
                        BlueWatchApp.requestHealthAuthorization()
                        
                    }
                    
                }
            
        }
        .navigationBarBackButtonHidden(true)
  
        
        
        
    }
    
    
   
    
    
        
}

#Preview {
    ContentView()
        .environmentObject(BLEManager.shared)
}


struct AppBackgroundStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background( // give the List a background to show
                LinearGradient(
                    gradient: Gradient(colors: [Color.BG_1, Color.BG_2]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
    }
}

private struct TextColorModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        if(colorScheme == .dark){
            content.foregroundStyle(Color(.text))
        }
    }
}

extension View {
    func appBackground() -> some View {
        self.modifier(AppBackgroundStyle())
    }
    func textColor() -> some View {
        self.modifier(TextColorModifier())
    }
}
