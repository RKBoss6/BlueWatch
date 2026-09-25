
import Charts
import SwiftData
import SwiftUI

struct LineChartView: View {

    let data: [ChartData]
    let color: Color
    let interactive: Bool
    let isTimewise: Bool
    let unitSuffix: String
    let xDomain: ClosedRange<Date>?
    let height: Double
    let timeAgoSeconds: Double
    let showPoints: Bool
    let hoursMarked: Int
    let showAverage: Bool
    let isThumbnail: Bool
    let date:Date
    @State private var selectedX: Date? = nil

    var timeRange: ClosedRange<Date> {
        if let xDomain {
            return xDomain
        }

        if !isThumbnail {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
                .addingTimeInterval(-1)
            return startOfDay...endOfDay
        }

        let now = Date()
        let dayAgo = now.addingTimeInterval(-self.timeAgoSeconds)
        return dayAgo...now
    }

    var displayedData: [ChartData] {
        data.filter { timeRange.contains($0.x) }
    }

    var displayedAverage: Double? {
        guard !displayedData.isEmpty && showAverage else { return nil }
        return displayedData.map(\.y).reduce(0, +) / Double(displayedData.count)
    }

    init(
        data: [ChartData],
        color: Color,
        isTimewise: Bool,
        unitSuffix: String,
        interactive: Bool,
        xDomain: ClosedRange<Date>? = nil,
        height: Double = 300,
        timeAgoSeconds: Double = 86400,
        showPoints: Bool = false,
        hoursMarked: Int = 6,
        showAverage: Bool,
        isThumbnail: Bool,
        date:Date = Date()
    ) {

        self.data = data
        self.color = color
        self.timeAgoSeconds = timeAgoSeconds
        self.isTimewise = isTimewise
        self.unitSuffix = unitSuffix
        self.interactive = interactive
        self.xDomain = xDomain
        self.height = height
        self.showPoints = showPoints
        self.hoursMarked = hoursMarked
        self.showAverage = showAverage
        self.isThumbnail = isThumbnail
        self.date = date
    }

    var body: some View {
        VStack {

            Chart {

                RuleMark(x: .value("Start", timeRange.lowerBound))
                    .foregroundStyle(.clear)

                RuleMark(x: .value("End", timeRange.upperBound))
                    .foregroundStyle(.clear)

                if let average = displayedAverage {
                    RuleMark(y: .value("Average", average))
                        .foregroundStyle(.gray)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
                }

                ForEach(displayedData) { item in

                    if showPoints {
                        LineMark(
                            x: .value("Time", item.x),
                            y: .value("Value", item.y)
                        )
                        .foregroundStyle(color)
                        .symbol(.circle)
                    } else {
                        LineMark(
                            x: .value("Time", item.x),
                            y: .value("Value", item.y)
                        )
                        .foregroundStyle(color)
                    }

                    AreaMark(
                        x: .value("Time", item.x),
                        y: .value("Value", item.y)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                color.opacity(0.4), .clear,
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }

                if interactive {
                    if let selectedX,
                       let selectedPoint = displayedData.min(by: {
                           abs($0.x.timeIntervalSince(selectedX))
                               < abs($1.x.timeIntervalSince(selectedX))
                       })
                    {

                        RuleMark(x: .value("Selected", selectedPoint.x))
                            .foregroundStyle(.gray.opacity(0.5))
                            .annotation(
                                position: .top,
                                overflowResolution: .init(x: .fit, y: .disabled)
                            ) {

                                VStack {

                                    if isTimewise {
                                        Text(
                                            selectedPoint.x.formatted(
                                                .dateTime.hour().minute()
                                            )
                                        )
                                        .font(
                                            .system(.caption, design: .rounded)
                                        )
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.gray)
                                    }

                                    Text(
                                        "\(selectedPoint.y, specifier: "%.0f")\(unitSuffix.isEmpty ? "" : "" + unitSuffix)"
                                    )
                                    .font(
                                        .system(.subheadline, design: .rounded)
                                            .bold()
                                    )

                                    if let avg = displayedAverage {
                                        Text(
                                            "Avg: \(avg, specifier: "%.0f")\(unitSuffix.isEmpty ? "" : "" + unitSuffix)"
                                        )
                                        .font(
                                            .system(.subheadline, design: .rounded)
                                                .bold()
                                        )
                                    }
                                }
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8).fill(
                                        Color(.systemBackground)
                                    )
                                    .shadow(radius: 2)
                                )
                            }
                    }
                }
            }

            .chartXAxis {
                AxisMarks(
                    values: .stride(
                        by: .hour,
                        count: Int(
                            round(
                                timeAgoSeconds / 60 / 60 / Double(hoursMarked)
                            )
                        )
                    )
                ) { value in
                    AxisGridLine()
                    AxisTick()

                    AxisValueLabel(
                        format: .dateTime.hour(.defaultDigits(amPM: .narrow))
                            .minute()
                    )
                }
            }

            .chartXScale(domain: timeRange)
            .chartXSelection(value: $selectedX)
            .frame(height: height)

            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel()
                }
            }
        }
        .padding()
    }
}

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
            self.height = 400
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

