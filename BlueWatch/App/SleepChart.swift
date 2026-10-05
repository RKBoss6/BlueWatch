//
//  SleepChart.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 10/5/26.
//

import Foundation
import Charts
import SwiftData
import SwiftUI

struct SleepChartView: View {
    let segments: [SleepSegment]
    let color: Color
    let interactive: Bool
    let height: Double
    let xDomain: ClosedRange<Date>?
    @State private var selectedX: Date? = nil

    private let barHalfHeight = 0.3

    init(
        segments: [SleepSegment],
        color: Color,
        interactive: Bool,
        xDomain: ClosedRange<Date>? = nil,
        height: Double = 300
    ) {
        self.segments = segments
        self.color = color
        self.interactive = interactive
        self.xDomain = xDomain
        self.height = height
    }

    // Fits the window to the night (whole hours), or a blank 8h window when empty.
    private var timeRange: ClosedRange<Date> {
        if let xDomain { return xDomain }
        guard let first = segments.first?.start, let last = segments.last?.end else {
            let now = Date()
            return now.addingTimeInterval(-8 * 3600)...now
        }
        let calendar = Calendar.current
        let lower = calendar.dateInterval(of: .hour, for: first)?.start ?? first
        let upper = calendar.dateInterval(of: .hour, for: last)?.end ?? last
        return lower...max(upper, lower.addingTimeInterval(3600))
    }

    private var hourStride: Int {
        let hours = timeRange.upperBound.timeIntervalSince(timeRange.lowerBound) / 3600
        return hours <= 6 ? 1 : (hours <= 12 ? 2 : 3)
    }

    private func fill(_ state: SleepState) -> Color {
        switch state {
        case .awake: return .graphOrange
        case .light: return color.opacity(0.55)
        case .deep: return color
        }
    }

    private struct Connector: Identifiable {
        let x: Date
        let from: SleepState
        let to: SleepState
        var id: Date { x }
    }

    // Links bars that touch (or nearly touch) in time.
    private var connectors: [Connector] {
        zip(segments, segments.dropFirst()).compactMap { a, b in
            guard b.start.timeIntervalSince(a.end) < 60, a.state != b.state else { return nil }
            return Connector(x: b.start, from: a.state, to: b.state)
        }
    }

    private var baseChart: some View {
        Chart {
            // Invisible rules pin the x range even when there is no data.
            RuleMark(x: .value("Start", timeRange.lowerBound))
                .foregroundStyle(.clear)
            RuleMark(x: .value("End", timeRange.upperBound))
                .foregroundStyle(.clear)

            ForEach(connectors) { c in
                let top = c.from.level > c.to.level ? c.from : c.to
                let bottom = c.from.level > c.to.level ? c.to : c.from
                RectangleMark(
                    x: .value("Time", c.x),
                    yStart: .value("Stage", bottom.level),
                    yEnd: .value("Stage", top.level),
                    width: .fixed(3)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [fill(top).opacity(0.6), fill(bottom).opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            ForEach(segments) { seg in
                RectangleMark(
                    xStart: .value("Start", seg.start),
                    xEnd: .value("End", seg.end),
                    yStart: .value("Stage", seg.state.level - barHalfHeight),
                    yEnd: .value("Stage", seg.state.level + barHalfHeight)
                )
                .cornerRadius(5)
                .foregroundStyle(fill(seg.state))
            }

            if interactive,
                let selectedX,
                let seg = segments.first(where: { $0.start <= selectedX && selectedX < $0.end })
            {
                RuleMark(x: .value("Selected", selectedX))
                    .foregroundStyle(.gray.opacity(0.5))
                    .annotation(
                        position: .top,
                        overflowResolution: .init(x: .fit, y: .disabled)
                    ) {
                        VStack {
                            Text(
                                "\(seg.start.formatted(.dateTime.hour().minute())) – \(seg.end.formatted(.dateTime.hour().minute()))"
                            )
                            .font(.system(.caption, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(.gray)
                            Text("\(seg.state.label) · \(SleepDay.durationString(seg.duration))")
                                .font(.system(.subheadline, design: .rounded).bold())
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground))
                                .shadow(radius: 2)
                        )
                    }
            }
        }
        .chartYScale(domain: -0.6...2.6)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: hourStride)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(
                    format: .dateTime.hour(.defaultDigits(amPM: .narrow)).minute()
                )
            }
        }
        .chartXScale(domain: timeRange)
        .chartXSelection(value: $selectedX)
        .frame(height: height)
    }

    var body: some View {
        VStack {
            // Stage names only when there's room (expanded view).
            if interactive {
                baseChart.chartYAxis {
                    AxisMarks(position: .leading, values: [2.0, 1.0, 0.0]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self),
                                let state = SleepState.allCases.first(where: { $0.level == v })
                            {
                                Text(state.label).font(.caption2)
                            }
                        }
                    }
                }
            } else {
                baseChart.chartYAxis {
                    AxisMarks(values: [2.0, 1.0, 0.0]) { _ in
                        AxisGridLine()
                    }
                }
            }
        }
        .padding()
    }
}

/// Query wrapper, the sleep counterpart of `DataChart`.
/// `day == nil` shows the most recent night; pass a date to show that day's night.
struct SleepDataChart: View {
    @Query private var days: [SleepDay]
    let color: Color
    let isThumbnail: Bool

    init(color: Color, isThumbnail: Bool, day: Date? = nil) {
        self.color = color
        self.isThumbnail = isThumbnail

        var descriptor: FetchDescriptor<SleepDay>
        if let day {
            let key = Calendar.current.startOfDay(for: day)
            descriptor = FetchDescriptor<SleepDay>(
                predicate: #Predicate<SleepDay> { $0.timestamp == key }
            )
        } else {
            descriptor = FetchDescriptor<SleepDay>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            descriptor.fetchLimit = 1
        }
        _days = Query(descriptor)
    }

    var body: some View {
        SleepChartView(
            segments: days.first?.segments ?? [],
            color: color,
            interactive: !isThumbnail,
            height: isThumbnail ? 160 : 500
        )
    }
}

/// Headline for the metric card ("7h 33m" + "Updated 7:02 AM").
struct SleepCardSummary: View {
    @Query private var latest: [SleepDay]

    init() {
        var descriptor = FetchDescriptor<SleepDay>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        _latest = Query(descriptor)
    }

    var body: some View {
        VStack {
            if let day = latest.first {
                Text(SleepDay.durationString(day.totalAsleep))
                    .font(.title2)
                    .fontWeight(.bold)
                Text(
                    "Updated \(day.lastUpdate?.formatted(date: .omitted, time: .shortened) ?? "--")"
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
        }
    }
}

#Preview {
    let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-2 * 3600)
    let samples: [(Int, SleepState)] = [
        (0, .awake), (10, .light), (50, .deep), (90, .light), (130, .deep),
        (170, .light), (230, .awake), (240, .light), (300, .deep), (340, .light),
        (400, .awake),
    ]
    let day = SleepDay(
        timestamp: start,
        samples: samples.map {
            SleepSample(
                timestamp: start.addingTimeInterval(Double($0.0) * 60),
                state: $0.1.rawValue
            )
        }
    )
    return SleepChartView(
        segments: day.segments,
        color: .indigo,
        interactive: true
    )
    .appBackground()
}



//
//  SleepData.swift
//  BlueWatch
//
//  Sleep storage: ONE `SleepDay` object per day, kept in the SwiftData store
//  alongside `DataPoint`. Each object holds the day's timestamp plus the list of
//  (timestamp, state) samples the watch reported.
//
//  Watch -> phone payload (added to the existing "health" JSON):
//      { "type": "health", "start": <ms>, "sleep": 2 | 3 | 4 }
//  State codes match the Bangle.js sleeplog statuses: 2 = awake, 3 = light, 4 = deep.
//  Anything else (unknown / not worn) is ignored.
//

import Foundation
import SwiftData

enum SleepState: Int, Codable, CaseIterable {
    case awake = 2
    case light = 3
    case deep = 4

    var label: String {
        switch self {
        case .awake: return "Awake"
        case .light: return "Light"
        case .deep: return "Deep"
        }
    }

    /// Chart row, top to bottom: awake (2), light (1), deep (0)
    var level: Double {
        switch self {
        case .awake: return 2
        case .light: return 1
        case .deep: return 0
        }
    }
}

struct SleepSample: Codable, Hashable {
    var timestamp: Date
    var state: Int  // SleepState.rawValue
}

@Model
final class SleepDay {
    /// Start of the calendar day this sleep ENDED on (see `dayKey(for:)`).
    var timestamp: Date
    var samples: [SleepSample]

    init(timestamp: Date, samples: [SleepSample] = []) {
        self.timestamp = timestamp
        self.samples = samples
    }
}

/// A contiguous stretch in one sleep state, ready to draw as a bar.
struct SleepSegment: Identifiable {
    let state: SleepState
    let start: Date
    let end: Date
    var id: Date { start }
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

extension SleepDay {
    /// A night spans midnight, so samples are grouped by the day you wake up:
    /// anything from 6 PM onward belongs to the next calendar day.
    static func dayKey(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date.addingTimeInterval(6 * 3600))
    }

    /// How long the final sample is assumed to last (watch reports roughly every 10 min).
    static let sampleInterval: TimeInterval = 10 * 60
    /// A sample never stretches past this, so a not-worn gap shows as empty space.
    static let maxGap: TimeInterval = 30 * 60

    var segments: [SleepSegment] {
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        var result: [SleepSegment] = []
        for (i, sample) in sorted.enumerated() {
            guard let state = SleepState(rawValue: sample.state) else { continue }
            let next: Date? = i + 1 < sorted.count ? sorted[i + 1].timestamp : nil
            let limit = sample.timestamp.addingTimeInterval(
                next == nil ? Self.sampleInterval : Self.maxGap
            )
            let end = min(next ?? limit, limit)
            if let last = result.last, last.state == state, last.end == sample.timestamp {
                result[result.count - 1] = SleepSegment(state: state, start: last.start, end: end)
            } else {
                result.append(SleepSegment(state: state, start: sample.timestamp, end: end))
            }
        }
        return result
    }

    /// Time asleep (light + deep), like Apple's "Time Asleep".
    var totalAsleep: TimeInterval {
        segments.filter { $0.state != .awake }.reduce(0) { $0 + $1.duration }
    }

    var lastUpdate: Date? {
        samples.map(\.timestamp).max()
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute]
        f.unitsStyle = .abbreviated
        f.zeroFormattingBehavior = .dropLeading
        return f
    }()

    static func durationString(_ interval: TimeInterval) -> String {
        durationFormatter.string(from: max(interval, 0)) ?? "--"
    }
}

enum SleepService {
    /// Mirrors `DataService.addDataPointInBackground`: appends a sample to that
    /// day's `SleepDay`, creating the day's object the first time.
    static func addSampleInBackground(timestamp: Date, state: Int) {
        guard SleepState(rawValue: state) != nil else { return }
        let container = DataManager.sharedContainer

        Task.detached(priority: .background) {
            let context = ModelContext(container)
            let key = SleepDay.dayKey(for: timestamp)
            let descriptor = FetchDescriptor<SleepDay>(
                predicate: #Predicate<SleepDay> { $0.timestamp == key }
            )

            let day: SleepDay
            if let existing = try? context.fetch(descriptor).first {
                day = existing
            } else {
                day = SleepDay(timestamp: key)
                context.insert(day)
            }

            // The watch can resend the same reading after a reconnect.
            if day.samples.contains(where: { $0.timestamp == timestamp }) { return }

            day.samples.append(SleepSample(timestamp: timestamp, state: state))
            try? context.save()
        }
    }
}
