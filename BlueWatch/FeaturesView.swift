//
//  FeaturesView.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 3/4/25.
//

import SwiftUI

struct FeatureCard: View {
    @Environment(\.colorScheme) var colorScheme
    let icon:String
    let description:String
    var body: some View {
        HStack{
            Image(systemName: icon)
                .font(.title)
                .fontWeight(.semibold)
                
            Text(description)
                .font(.body)
                .fontWeight(.semibold)
                
            Spacer()
            
        }
        
        .padding()
        .foregroundStyle(colorScheme == .dark ? .white : .black)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color("SecondaryColor")))
    }
}

#Preview {
    FeatureCard(icon:"gear",description:"Change settings anywhere")
        
}
