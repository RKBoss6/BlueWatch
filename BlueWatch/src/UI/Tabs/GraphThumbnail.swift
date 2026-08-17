//
//  GraphThumbnail.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 8/16/26.
//

import SwiftUI

struct GraphThumbnail: View {
    @Environment(\.isPreview) var isPreview
    let data:DataType
    let color: Color
    let thumbnailName: String
    let expandedName: String
    var body: some View {
        VStack{
            NavigationLink{
                ExpandedMetricView(title: expandedName, dataType: isPreview ? .test : data, color: color)
            }label:{
                HStack{
                    Text(thumbnailName)
                        .font(.headline)
                        .frame(maxWidth: .infinity,alignment: .leading)
                        .padding(.leading,10)
                        .bold()
                        .tint(.primary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                    Image(systemName: "arrowshape.right")
                        .bold()
                        .font(.title3)
                        .tint(color)
                }
            }
            DataChart(dataType: isPreview ? .test : data, color: color)
                .padding(.bottom,70)
        }
    }
}

#Preview {
    NavigationStack{
        Grid{
            GraphThumbnail(data:.activeCalories, color:.green, thumbnailName: "Calories", expandedName: "Active calories")
            
            
        }
        .appBackground()
    }
}
    
