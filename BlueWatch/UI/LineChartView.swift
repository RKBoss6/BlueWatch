import SwiftUI
import _SwiftData_SwiftUI
import Charts

struct LineChartView: View {
    let data: [ChartData]
    let color: Color
    let isTimewise: Bool
    let unitSuffix: String
    
    @State private var selectedX: Date? = nil

    // Helper to define the fixed 24-hour window
    var timeRange: ClosedRange<Date> {
        let now = Date()
        let dayAgo = now.addingTimeInterval(-86400)
        return dayAgo...now
    }

    var body: some View {
        VStack {
            Chart {
                // Draw invisible points at the start/end to ensure the 24h grid shows even if empty
                RuleMark(x: .value("Start", timeRange.lowerBound))
                    .foregroundStyle(.clear)
                RuleMark(x: .value("End", timeRange.upperBound))
                    .foregroundStyle(.clear)

                ForEach(data) { item in
                    LineMark(
                        x: .value("Time", item.x),
                        y: .value("Value", item.y)
                    )
                    .foregroundStyle(color)
                    .symbol(.circle)
                    
                    AreaMark(
                        x: .value("Time", item.x),
                        y: .value("Value", item.y)
                    )
                    .foregroundStyle(LinearGradient(
                        gradient: Gradient(colors: [color.opacity(0.4), .clear]),
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                }

                if let selectedX, let selectedPoint = data.min(by: { abs($0.x.timeIntervalSince(selectedX)) < abs($1.x.timeIntervalSince(selectedX)) }) {
                    RuleMark(x: .value("Selected", selectedPoint.x))
                        .foregroundStyle(.gray.opacity(0.5))
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            VStack {
                                if isTimewise {
                                    Text(selectedPoint.x.formatted(.dateTime.hour().minute()))
                                        .font(.system(.caption, design: .rounded)).fontWeight(.semibold).foregroundStyle(.gray)
                                }
                                Text("\(selectedPoint.y, specifier: "%.0f")\(unitSuffix.isEmpty ? "" : "" + unitSuffix)")
                                    .font(.system(.subheadline, design: .rounded).bold())
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground)).shadow(radius: 2))
                        }
                }
            }
            .chartXAxis {
                // 'stride' ensures we hit the top of the hour. 'count: 3' shows every 3 hours to avoid crowding.
                AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                    AxisGridLine()
                    AxisTick()
                    // This will now show clean times like 12:00, 16:00, etc.
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute())
                }
            }
            // Forces the chart to always show the full 24-hour window
            .chartXScale(domain: timeRange)
            .chartXSelection(value: $selectedX)
            .frame(height: 300)
        }
        .padding()
    }
}

struct ChartData: Identifiable {
    let id = UUID()
    let x: Date
    let y: Double
}





struct DynamicDataChart: View {
    @Query private var filteredPoints: [DataPoint]
    let color: Color
    let suffix: String

    init(dataType: DataType, color: Color, suffix: String) {
        self.color = color
        self.suffix = suffix
        
        // This is how you dynamically filter a Query
        let typeRawValue = dataType.rawValue
        let dayAgo = Date().addingTimeInterval(-86400)
        
        let predicate = #Predicate<DataPoint> { point in
            point.rawType == typeRawValue && point.timestamp > dayAgo
        }
        
        // Initialize the Query with our custom predicate
        _filteredPoints = Query(filter: predicate, sort: \DataPoint.timestamp)
    }

    var body: some View {
        LineChartView(
            data: filteredPoints.map { ChartData(x: $0.timestamp, y: $0.value) },
            color: color,
            isTimewise: true,
            unitSuffix: suffix
        )
    }
}

#Preview {
    // Sort data by date so the Scale Domain works correctly
    let mockData = [
        ChartData(x: Date().addingTimeInterval(-10800), y: 10),
        ChartData(x: Date().addingTimeInterval(-7200), y: 25),
        ChartData(x: Date().addingTimeInterval(-3600), y: 15),
        ChartData(x: Date(), y: 30)
    ].sorted(by: { $0.x < $1.x })
    
    return DynamicDataChart(dataType: .heartRate, color: .red, suffix: "bpm")
}
