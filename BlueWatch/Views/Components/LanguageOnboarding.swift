//
//  WhatsNewView.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 8/21/26.
//

import SwiftUI

struct LanguageOnboarding: View {
    var body: some View {
        VStack{
            Spacer()

            HStack{
                Image(systemName:"globe")
                .font(.title)

                Text("App Languages")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding()
            }
            Spacer()

            Text("BlueWatch can support different localizations and languages, depending on the system language set.")
                .multilineTextAlignment(.center)
                .padding(.bottom)
            Text("The current languages supported are: ").multilineTextAlignment(.center)
            
            Text(verbatim: "English, Français, Español, Hindi (हिन्दी), and Deutsch")                .multilineTextAlignment(.center)
                .bold()
                .padding(.bottom)
            Text("Most translations are auto-generated, and errors may be present. If you'd like to fix errors/add new languages, look at the [BlueWatch Localization Info](https://github.com/RKBoss6/BlueWatch/blob/main/CONTRIBUTING.md#localizations), and open a PR to help improve the app!")
                .multilineTextAlignment(.center)
            
            Spacer()
            Spacer()


        }.padding()
            .appBackground()
            .presentationDetents([.medium])
        
    }
        
}

#Preview {
    LanguageOnboarding()
}
    
