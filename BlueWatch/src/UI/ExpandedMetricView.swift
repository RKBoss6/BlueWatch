//
//  ExpandedMetricView.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 7/24/26.
//

import SwiftUI
import _SwiftData_SwiftUI

struct ExpandedMetricView: View {
    let title: String
    let dataType: DataType
    let color:Color
    @Query private var filteredPoints: [DataPoint]
    @State private var selectedDay = Date()
    
    private var calendar: Calendar {
        Calendar.current
    }
    
    private var dayRange: ClosedRange<Date> {
        let start = calendar.startOfDay(for: selectedDay)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        return start...end
    }
    
    private var displayDate: String {
        selectedDay.formatted(.dateTime.month(.abbreviated).day().year())
    }
    
    
    
    private var unitSuffix: String {
        switch dataType {
        case .heartRate:
            return " bpm"
        case .steps:
            return " steps"
        case .battery:
            return "%"
        case .test, .bluetoothBoundary:
            return ""
        }
    }
    
    private var chartData: [ChartData] {
        if dataType == .test {
            return mockData(for: selectedDay)
        }
        
        let range = dayRange
        return filteredPoints
            .filter { range.contains($0.timestamp) }
            .map { ChartData(x: $0.timestamp, y: $0.value) }
    }
    
    init(title: String, dataType: DataType, color:Color) {
        self.title = title
        self.dataType = dataType
        self.color = color
        let typeRawValue = dataType.rawValue
        let predicate = #Predicate<DataPoint> { point in
            point.rawType == typeRawValue
        }
        
        _filteredPoints = Query(filter: predicate, sort: \DataPoint.timestamp)
    }
    
    var body: some View {
        VStack{
            
            Spacer()
            LineChartView(
                data: chartData,
                color: color,
                isTimewise: true,
                unitSuffix: unitSuffix,
                xDomain: dayRange
            )
            Divider()
            Spacer()
            HStack{
                Spacer()
                Button(action: {
                    moveDay(by: -1)
                }) {
                    Image(systemName: "arrowshape.left")
                        .font(.title) // Changes icon size
                        .tint(color) // Changes icon color
                }
                Spacer()
                Text(displayDate)
                Spacer()
                Button(action: {
                    moveDay(by: 1)
                }) {
                    Image(systemName: "arrowshape.right")
                        .font(.title) // Changes icon size
                        .tint(color)
                }
                .disabled(calendar.isDateInToday(selectedDay))
                .opacity(calendar.isDateInToday(selectedDay) ? 0.4 : 1)
                Spacer()
            }
            Spacer()
            
        }.appBackground()
            .navigationTitle(title)
    }
    
    private func moveDay(by value: Int) {
        guard let newDay = calendar.date(byAdding: .day, value: value, to: selectedDay) else {
            return
        }
        
        selectedDay = min(newDay, Date())
    }
    
    private func mockData(for day: Date) -> [ChartData] {
        let start = calendar.startOfDay(for: day)
        return [
            ChartData(x: start.addingTimeInterval(60 * 60), y: 58),
            ChartData(x: start.addingTimeInterval(4 * 60 * 60), y: 55),
            ChartData(x: start.addingTimeInterval(7 * 60 * 60), y: 74),
            ChartData(x: start.addingTimeInterval(10 * 60 * 60), y: 135),
            ChartData(x: start.addingTimeInterval(11 * 60 * 60), y: 162),
            ChartData(x: start.addingTimeInterval(13 * 60 * 60), y: 95),
            ChartData(x: start.addingTimeInterval(16 * 60 * 60), y: 70),
            ChartData(x: start.addingTimeInterval(19 * 60 * 60), y: 104),
            ChartData(x: start.addingTimeInterval(22 * 60 * 60), y: 67),
            ChartData(x: start.addingTimeInterval(23 * 60 * 60), y: 63)
        ]
    }
}

#Preview {
    ExpandedMetricView(title: "Heart Rate", dataType: .test, color:.graphRed)
}
