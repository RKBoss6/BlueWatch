//
//  FeaturesView.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 3/4/25.
//

import SwiftUI

struct FeatureCard: View {
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
        .foregroundStyle(.white)
        .background(.tint,in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    FeatureCard(icon:"gear",description:"Change settings anywhere")
        
}
