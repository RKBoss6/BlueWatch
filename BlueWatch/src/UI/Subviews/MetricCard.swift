//
//  MetricCard.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 8/18/26.
//

import SwiftUI
import SwiftData
struct MetricCard: View {
    @Environment(\.isPreview) var isPreview
    let dataType:DataType
    let color:Color
    let thumbTitle:String
    let expandedTitle:String
    @State var lastDataTimestampStr:String = "---"
    @State var lastDataValueStr:String = "--"
    @Query private var latestPoints: [DataPoint]
    init(
        dataType: DataType,
        color: Color,
        thumbTitle: String,
        expandedTitle: String
    ) {
        self.dataType = dataType
        self.color = color
        self.thumbTitle = thumbTitle
        self.expandedTitle = expandedTitle

        let rawType = dataType.rawValue

        var descriptor = FetchDescriptor<DataPoint>(
            predicate: #Predicate<DataPoint> {
                $0.rawType == rawType
            },
            sortBy: [
                SortDescriptor(\.timestamp, order: .reverse)
            ]
        )

        descriptor.fetchLimit = 1

        _latestPoints = Query(descriptor)
    }
    var body: some View {
        NavigationLink(destination: ExpandedMetricView(title: expandedTitle, dataType: isPreview ? .test : dataType, color: color)){
            ZStack{
                Rectangle()
                    .foregroundStyle(.clear)
                    .liquidGlass(cornerRadius:25)
                    .opacity(0.7)
                VStack{
                    Text(thumbTitle)
                        .font(.subheadline)
                    if let latestPoint = latestPoints.first {
                        Text(latestPoint.value.formatted()+(dataType == .battery ? "%" : ""))
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Latest: \(latestPoint.timestamp.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom)
                    }else{
                        Text("--")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Latest: --")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom)
                    }
                    
                    DataChart(dataType: isPreview ? .test : dataType, color:color, isThumbnail: true)
                        .padding(-20)
                        .allowsHitTesting(false)
                    
                    
                    
                    
                }
                .padding()
                
                
            }
        }
        .foregroundStyle(.primary)
       
    }
        
}

#Preview {
    NavigationStack{
        ScrollView{
            
            Grid{
                GridRow{
                    MetricCard(dataType: .test, color: .graphRed, thumbTitle: "Heart Rate", expandedTitle: "Heart Rate")
                    
                    MetricCard(dataType: .test, color: .graphRed, thumbTitle: "Heart Rate", expandedTitle: "Heart Rate")
                }
                .padding(.bottom,8)
                GridRow{
                    MetricCard(dataType: .test, color: .graphRed, thumbTitle: "Heart Rate", expandedTitle: "Heart Rate")
                    MetricCard(dataType: .test, color: .graphRed, thumbTitle: "Heart Rate", expandedTitle: "Heart Rate")
                }
            }
            .padding()
        }
        .appBackground()
    }
        
    
}
