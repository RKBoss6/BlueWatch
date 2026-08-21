//
//  WhatsNewView.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 8/21/26.
//

import SwiftUI

struct WhatsNewView: View {
    var body: some View {
        VStack{
            HStack{
                Image(systemName:"globe")
                .font(.title)

                Text("Languages")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding()
            }
            Text("Starting in BlueWatch v1.4.2, different Localizations are available, depending on system language.")
                .multilineTextAlignment(.center)
                .padding(.bottom)
            Text("The current languages supported are: ")                .multilineTextAlignment(.center)
            
            Text(verbatim: "English, Français, and Deutsch")                .multilineTextAlignment(.center)
                .bold()
                .padding(.bottom)
            Text("Most translations are auto-generated, and errors can appear. If you'd like to fix errors/add new languages, look at the [BlueWatch Localization Info](https://github.com/RKBoss6/BlueWatch/blob/main/CONTRIBUTING.md#localizations), and open a PR to help improve the app!")
                .multilineTextAlignment(.center)
            

        }.padding()
    }
}

#Preview {
    WhatsNewView()
}
    
