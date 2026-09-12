//
//  WatchScreen.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 3/4/25.
//
import SwiftUI
import StoreKit
import SwiftData


struct MetricThumbView: View {
    let id: ReorderableString
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        MetricCard(
            dataType: .heartRate,
            color: .graphRed,
            thumbTitle: "Heart Rate",
            expandedTitle: "Heart Rate"
        )
        /*
        
         */
    }
}
struct WatchScreen: View {
    private static let metricConfigs: [String: MetricCardConfig] = [
        "heartRate":       .init(dataType: .heartRate,       color: .graphRed,    thumbTitle: "Heart Rate",       expandedTitle: "Heart Rate"),
        "steps":           .init(dataType: .steps,           color: .graphPurple, thumbTitle: "Steps",            expandedTitle: "Steps"),
        "activeCalories":  .init(dataType: .activeCalories,  color: .graphOrange, thumbTitle: "Active Calories",  expandedTitle: "Active Calories"),
        "restingCalories": .init(dataType: .restingCalories, color: .graphBlue,   thumbTitle: "Resting Calories", expandedTitle: "Resting (BMR) Calories"),
        "battery":         .init(dataType: .battery,         color: .graphGreen,  thumbTitle: "Battery",          expandedTitle: "Watch Battery"),
    ]
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.isPreview) var isPreview
    @Environment(\.requestReview) var requestReview
    @Environment(\.modelContext) private var modelContext
    var vm: ViewModel = ViewModel.shared
    @AppStorage("metricCardStringOrder") var metricCardStringOrder=ReorderableListContainer(  [ReorderableString("heartRate"), ReorderableString("steps"), ReorderableString("activeCalories"), ReorderableString("restingCalories"), ReorderableString("battery")])
    @State private var visibleMetricItems: [ReorderableString] = []

    private func recomputeVisibleMetrics() {
        visibleMetricItems = metricCardStringOrder.items.filter { item in
            switch item.value {
            case "heartRate":       return settings.showHrThumb
            case "steps":           return settings.showStepsThumb
            case "activeCalories":  return settings.showActiveCalThumb
            case "restingCalories": return settings.showRestingCalThumb
            case "battery":         return settings.showBatteryThumb
            default:                return false
            }
        }
    }
    @ObservedObject var settings = Settings.shared
    @Environment(\.scenePhase) var scenePhase
    var authManager: AuthManager = AuthManager.shared
    private var CI = CommandInterpreter()
    @State private var findingPhone = false
    @EnvironmentObject var bleManager: BLEManager
    @ObservedObject private var ld: LocalData = LocalData.shared
    @State private var findingWatch = false
    private var findPhoneAlarm = FindPhoneAlarm()
    func getBattImg(battStr: String) -> String {
        var img: String = "battery.0percent"
        if let batt = Double(battStr) {
            // has a percentageb
            if batt > 5 {
                img = "battery.25percent"
            }
            if batt > 40 {
                img = "battery.50percent"
            }
            if batt > 70 {
                img = "battery.75percent"
            }
            if batt > 90 {
                img = "battery.100percent"
            }

        }
        return img
    }
   
    func getConnectButtonText() -> String {
        var text = ""
        if bleManager.isConnected {
            if bleManager.handshakeSuccessful {
                text = "Disconnect"
            } else {
                // Always "Retry", never a non-actionable "In progress" state.
                // isHandshaking can be true because a retry attempt got stranded
                // (the retry timer doesn't survive the app being suspended), and
                // in that exact case a manual tap needs to be able to do something.
                text = "Retry"
            }
        } else {
            text = "Connect"
        }
        return text
    }
    var body: some View {
        ZStack {
            ScrollView {
                LazyVStack(spacing: 20) {

                    Spacer()
                        .padding()
                    if !authManager.isLocationAuthorizedAlways {
                        ZStack {
                            RoundedRectangle(cornerRadius: 24)
                                .foregroundStyle(.graphRed)
                                .opacity(0.15)
                                .shadow(
                                    color: .black.opacity(0.8),
                                    radius: 40,
                                    x: 0,
                                    y: 0
                                )
                            Text(
                                "Location permissions are not set to 'always'. This may result in background location & weather not sending. You can change this in system settings."
                            )
                            .font(.footnote)
                            .multilineTextAlignment(.center).padding()
                        }
                        .padding(.top)
                        .padding(.bottom, -30)
                        .padding(.horizontal)
                    }
                    Image(
                        vm.savedDevice == "Bangle.js 2"
                            ? "BangleJS2" : "BangleJS1"
                    )
                    .resizable()
                    .frame(width: 200, height: 200)
                    .padding(.top, 50)
                    HStack {
                        Text(
                            settings.deviceName.isEmpty == false
                                ? settings.deviceName : vm.savedDevice
                        )
                        .font(.title)
                        .fontWeight(.bold)
                        Spacer()
                        Image(systemName: getBattImg(battStr: ld.battery))
                        Text(ld.battery + "%")
                    }
                    .padding()
                    .padding(.horizontal)

                    /*
                     Text("Last message:")
                     .font(.caption)

                     Text(bleManager.lastMessage)
                     .padding()
                     .frame(maxWidth: .infinity)
                     .background(Color.gray.opacity(0.1))
                     .cornerRadius(8)
                     */
                    HStack {
                        Text(bleManager.status)
                            .foregroundColor(
                                bleManager.isConnected ? .green : .orange
                            )
                        Spacer()

                        Button(getConnectButtonText()) {

                            if bleManager.isConnected {
                                if bleManager.handshakeSuccessful {
                                    bleManager.stop(destructive: true)
                                } else {
                                    // Always force a fresh attempt. isHandshaking may
                                    // already be true from a stranded retry (see
                                    // startHandshake's doc comment) — that's precisely
                                    // the case this button needs to be able to fix.
                                    bleManager.startHandshake(force: true)
                                }
                            } else {
                                bleManager.start()
                                bleManager.connect()
                            }

                        }
                        .buttonStyle(.borderedProminent)
                        .buttonStyle(.bordered)

                    }

                    .padding(.leading)
                    .padding(.trailing)
                    .padding(.horizontal)

                    .padding(.top, -10)
                    Divider()
                    ZStack {
                        ScrollView(.horizontal) {
                            HStack {

                                Button {
                                    if findingWatch {
                                        bleManager.send("Stop Find Watch")
                                        findingWatch = false
                                    } else {
                                        bleManager.send("Find Watch")
                                        findingWatch = true
                                    }

                                } label: {
                                    HStack {
                                        Image(systemName: "ipod.and.applewatch")
                                        Text(
                                            findingWatch
                                                ? "Stop Finding" : "Find Watch"
                                        )

                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(10)

                                }
                                .disabled(!isPreview && !bleManager.isConnected)

                                .buttonStyle(.borderedProminent)
                                .tint(findingWatch ? .orange : .accent)
                                .padding(.leading)

                                Button {
                                    Task {
                                        await LocationManager.shared
                                            .sendLocation()
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "location.fill")
                                        Text("Push Location")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(10)

                                }
                                .disabled(!isPreview && !bleManager.isConnected)
                                .buttonStyle(.borderedProminent)

                                Button {
                                    Task {
                                        await WeatherManager.shared
                                            .updateWeatherAndSend()
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "cloud.sun.fill")
                                        Text("Push Weather")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(10)

                                }
                                .disabled(!isPreview && !bleManager.isConnected)
                                .buttonStyle(.borderedProminent)
                                .padding(.trailing)
                            }
                        }

                        HStack {
                            Rectangle()
                                .fill(.ultraThickMaterial)
                                .frame(width: 20)
                                .overlay(
                                    .white.opacity(
                                        colorScheme == .dark ? 0.15 : 0
                                    )
                                )
                                .mask(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            .black, .clear,
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            Spacer()
                            Rectangle()
                                .fill(.ultraThickMaterial)
                                .frame(width: 20)
                                .overlay(
                                    .white.opacity(
                                        colorScheme == .dark ? 0.15 : 0
                                    )
                                )
                                .mask(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            .black, .clear,
                                        ]),
                                        startPoint: .trailing,
                                        endPoint: .leading
                                    )
                                )
                        }
                        .ignoresSafeArea(edges: .all)
                    }
                    .ignoresSafeArea(edges: .leading)
                    Divider()

                    Text("Metrics")
                        .font(.title3)
                        .bold()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                        .padding(.leading, 10)
                    if #available(iOS 27.0, *) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200))], spacing: 10) {
                            
                                ForEach(visibleMetricItems) { str in
                                    let cfg = Self.metricConfigs[str.value]!
                                    MetricCard(
                                        dataType: cfg.dataType,
                                        color: cfg.color,
                                        thumbTitle: cfg.thumbTitle,
                                        expandedTitle: cfg.expandedTitle
                                    )
                                }
                                .reorderable()
                            
                        }
                        .padding(.horizontal)
                        .reorderContainer(for: ReorderableString.self) { difference in
                            var updatedOrder = metricCardStringOrder
                            updatedOrder.apply(difference: difference)
                            metricCardStringOrder = updatedOrder
                        }
                    } else {
                        // Fallback on earlier versions
                        LazyVGrid(
                           columns: [
                               GridItem(.adaptive(minimum: 150, maximum: 200))
                           ],
                           spacing: 10
                       ) {
                           if Settings.shared.showHrThumb {
                               MetricCard(
                                   dataType: .heartRate,
                                   color: .graphRed,
                                   thumbTitle: "Heart Rate",
                                   expandedTitle: "Heart Rate"
                               )
                           }
                           if Settings.shared.showStepsThumb {
                               MetricCard(
                                   dataType: .steps,
                                   color: .graphPurple,
                                   thumbTitle: "Steps",
                                   expandedTitle: "Steps"
                               )
                           }
                           if Settings.shared.showActiveCalThumb {
                               MetricCard(
                                   dataType: .activeCalories,
                                   color: .graphOrange,
                                   thumbTitle: "Active Calories",
                                   expandedTitle: "Active Calories"
                               )
                           }
                           if Settings.shared.showRestingCalThumb {
                               MetricCard(
                                   dataType: .restingCalories,
                                   color: .graphBlue,
                                   thumbTitle: "Resting Calories",
                                   expandedTitle: "Resting (BMR) Calories"
                               )
                           }
                           if Settings.shared.showBatteryThumb {
                               MetricCard(
                                   dataType: .battery,
                                   color: .graphGreen,
                                   thumbTitle: "Battery",
                                   expandedTitle: "Watch Battery"
                               )
                           }

                       }
                       .padding(.horizontal)
                    }

                    Spacer()
                        .padding(35)

                }

                .padding(.bottom)
                Spacer()

            }
            .scrollIndicators(.hidden)  // Hides indicators for this ScrollView
            .ignoresSafeArea(.all)

            .appBackground()
            VStack {
                Rectangle()
                    .fill(.ultraThickMaterial)
                    .frame(height: 100)
                    .overlay(.white.opacity(colorScheme == .dark ? 0.15 : 0))
                    .mask(
                        LinearGradient(
                            gradient: Gradient(colors: [.black, .clear]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Spacer()
            }
            .ignoresSafeArea()
        }
        .onAppear { recomputeVisibleMetrics() }
        .onChange(of: settings.showHrThumb) { recomputeVisibleMetrics() }
        .onChange(of: settings.showStepsThumb) { recomputeVisibleMetrics() }
        .onChange(of: settings.showActiveCalThumb) { recomputeVisibleMetrics() }
        .onChange(of: settings.showRestingCalThumb) { recomputeVisibleMetrics() }
        .onChange(of: settings.showBatteryThumb) { recomputeVisibleMetrics() }
        .onChange(of: metricCardStringOrder.rawValue) { recomputeVisibleMetrics() }
        .onAppear {
            AppMetricManager.shared.tryTriggerReview(
                requestReviewAction: requestReview
            )
        }

    }
}

#Preview {
    NavigationStack{
        WatchScreen()
            .environmentObject(BLEManager.shared)
    }
}
