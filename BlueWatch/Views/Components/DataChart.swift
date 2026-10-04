//
//  DataChart.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 10/3/26.
//

import Foundation
import SwiftUI
import _SwiftData_SwiftUI
struct ChartData: Identifiable {

    let id = UUID()
    let x: Date
    let y: Double
}

struct DataChart: View {

    @Query private var filteredPoints: [DataPoint]

    let color: Color
    let suffix: String
    let interactive: Bool
    let height: Double
    let timeAgoSeconds: Double
    let dataType: DataType
    let isThumbnail: Bool
    let showMarkers: Bool
    let hourlyMarkers: Int
    let showAverage: Bool
    let date:Date
    init(dataType: DataType, color: Color, isThumbnail: Bool, showAverage:Bool = false, date:Date = Date()) {

        self.color = color
        self.isThumbnail = isThumbnail
        self.suffix = Utils.unitSuffix(dataType: dataType)
        self.dataType = dataType
        self.date=date
        if isThumbnail {

            self.interactive = false
            self.height = 160
            self.showMarkers = false
            self.timeAgoSeconds = 12 * 60 * 60
            self.hourlyMarkers = 3

        } else {

            self.interactive = true
            self.height = 460
            self.showMarkers = true
            self.timeAgoSeconds = 86400
            self.hourlyMarkers = 6
        }

        self.showAverage = showAverage

        let typeRawValue = dataType.rawValue

        let dayAgo: Date

        if isThumbnail {
            dayAgo = Date().addingTimeInterval(-self.timeAgoSeconds)
        } else {
            dayAgo = Calendar.current.startOfDay(for: date)
        }

        let boundaryRawValue = DataType.bluetoothBoundary.rawValue

        let predicate = #Predicate<DataPoint> { point in
            (point.rawType == typeRawValue || point.rawType == boundaryRawValue)
                && point.timestamp > dayAgo
        }

        _filteredPoints = Query(
            filter: predicate,
            sort: \DataPoint.timestamp
        )
    }

    var body: some View {

        if dataType == .test {

            let now = Date()

            let mockPoints: [ChartData] = [

                ChartData(x: now.addingTimeInterval(-80000), y: 58),
                ChartData(x: now.addingTimeInterval(-72000), y: 55),
                ChartData(x: now.addingTimeInterval(-65000), y: 54),
                ChartData(x: now.addingTimeInterval(-58000), y: 60),
                ChartData(x: now.addingTimeInterval(-50000), y: 57),
                ChartData(x: now.addingTimeInterval(-45000), y: 72),
                ChartData(x: now.addingTimeInterval(-40000), y: 85),
                ChartData(x: now.addingTimeInterval(-36000), y: 135),
                ChartData(x: now.addingTimeInterval(-35000), y: 158),
                ChartData(x: now.addingTimeInterval(-34000), y: 162),
                ChartData(x: now.addingTimeInterval(-33000), y: 140),
                ChartData(x: now.addingTimeInterval(-30000), y: 95),
                ChartData(x: now.addingTimeInterval(-25000), y: 78),
                ChartData(x: now.addingTimeInterval(-20000), y: 70),
                ChartData(x: now.addingTimeInterval(-16000), y: 68),
                ChartData(x: now.addingTimeInterval(-12000), y: 74),
                ChartData(x: now.addingTimeInterval(-8000), y: 92),
                ChartData(x: now.addingTimeInterval(-5000), y: 104),
                ChartData(x: now.addingTimeInterval(-2000), y: 67),
                ChartData(x: now, y: 63),

            ].sorted(by: { $0.x < $1.x })

            LineChartView(
                data: mockPoints,
                color: color,
                isTimewise: true,
                unitSuffix: suffix,
                interactive: interactive,
                height: height,
                timeAgoSeconds: timeAgoSeconds,
                hoursMarked: hourlyMarkers,
                showAverage: showAverage,
                isThumbnail: isThumbnail,
                date:date

            )

        } else {

            let chartData = filteredPoints.map {
                ChartData(x: $0.timestamp, y: $0.value)
            }

            LineChartView(
                data: chartData,
                color: color,
                isTimewise: true,
                unitSuffix: suffix,
                interactive: interactive,
                height: height,
                timeAgoSeconds: timeAgoSeconds,
                hoursMarked: hourlyMarkers,
                showAverage: showAverage,
                isThumbnail: isThumbnail,
                date:date
            )
        }
    }
}

#Preview {
    DataChart(dataType: .test, color: .graphRed, isThumbnail: false)
        .appBackground()
}

