//
//  MetricCard.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 8/18/26.
//

import SwiftData
import SwiftUI
struct MetricCardConfig {
    let dataType: DataType
    let color: Color
    let thumbTitle: String
    let expandedTitle: String
}
struct MetricCard: View {
    
    @Environment(\.isPreview) var isPreview
    let dataType: DataType
    let color: Color
    let thumbTitle: String
    let expandedTitle: String
    @State var lastDataTimestampStr: String = "---"
    @State var lastDataValueStr: String = "--"
    @Query private var latestPoints: [DataPoint]
    func automaticRelativeString(date: Date) -> String {
        let calendar = Calendar.current
        
        // 1. Force "today" to prevent "now" or "hours ago"
        if calendar.isDateInToday(date) {
            return "today"
        }
        
        // 2. Strip the hours/minutes/seconds from both dates to lock into day units
        let startOfTargetDate = calendar.startOfDay(for: date)
        let startOfToday = calendar.startOfDay(for: Date())
        
        // 3. Use the formatter with normalized dates
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        
        return formatter.localizedString(for: startOfTargetDate, relativeTo: startOfToday)
    }

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
        NavigationLink(
            destination: ExpandedMetricView(
                title: expandedTitle,
                dataType: dataType,
                color: color
            )
        ) {
            ZStack {
                Rectangle()
                    .foregroundStyle(.clear)
                    .liquidGlass(cornerRadius: 25)
                    .opacity(0.7)
                VStack {
                    Text(thumbTitle)
                        .font(.subheadline)
                    if let latestPoint = latestPoints.first {
                        Text(
                            latestPoint.value.formatted(.number.precision(.fractionLength(0)))
                                + (dataType == .battery ? "%" : "")
                        )
                        .font(.title2)
                        .fontWeight(.bold)

                        Text(
                            "Updated \(dataType != .hrv ? latestPoint.timestamp.formatted(date: .omitted, time: .shortened) : automaticRelativeString(date: latestPoint.timestamp))"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom)
                    } else {
                        Text("--")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Updated --")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom)
                    }

                    DataChart(
                        dataType: dataType,
                        color: color,
                        isThumbnail: true
                    )
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
    NavigationStack {
        ScrollView {

            Grid {
                GridRow {
                    MetricCard(
                        dataType: .test,
                        color: .graphRed,
                        thumbTitle: "Heart Rate",
                        expandedTitle: "Heart Rate"
                    )

                    MetricCard(
                        dataType: .test,
                        color: .graphRed,
                        thumbTitle: "Heart Rate",
                        expandedTitle: "Heart Rate"
                    )
                }
                .padding(.bottom, 8)
                GridRow {
                    MetricCard(
                        dataType: .test,
                        color: .graphRed,
                        thumbTitle: "Heart Rate",
                        expandedTitle: "Heart Rate"
                    )
                    MetricCard(
                        dataType: .test,
                        color: .graphRed,
                        thumbTitle: "Heart Rate",
                        expandedTitle: "Heart Rate"
                    )
                }
            }
            .padding()
        }
        .appBackground()
    }

}
