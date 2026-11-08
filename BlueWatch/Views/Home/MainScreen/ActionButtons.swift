//
//  ActionButtons.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 11/7/26.
//

import SwiftUI

struct ActionButtons: View {
    @ObservedObject var bleManager = BLEManager.shared
    @State private var findingWatch = false
    @Environment(\.isPreview) var isPreview
    @State private var showLocationConfirmation = false
    @State private var showTimeConfirmation = false
    @State private var showWeatherConfirmation = false

    var body: some View {
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
                        Image(
                            systemName: "applewatch.radiowaves.left.and.right"
                        )
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
                    DataSendManager.sendCurrentTime()
                    showTimeConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "clock.fill")
                        Text("Update Time")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)

                }
                .disabled(!isPreview && !bleManager.isConnected)
                .buttonStyle(.borderedProminent)
                .tint(.accent)
                .alert(
                    "Successfully updated time!",
                    isPresented: $showTimeConfirmation
                ) {
                    // Default action button
                    Button("OK", role: .cancel) {

                    }
                    .tint(.primary)

                }
                Button {
                    DataSendManager.sendCurrentLocation()
                    showLocationConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "location.fill")
                        Text("Push Location")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)

                }
                .tint(.accent)

                .disabled(!isPreview && !bleManager.isConnected)
                .buttonStyle(.borderedProminent)
                .alert(
                    "Successfully updated location!",
                    isPresented: $showLocationConfirmation
                ) {
                    // Default action button
                    Button("OK", role: .cancel) {

                    }
                    .tint(.primary)

                }

                Button {
                    DataSendManager.sendCurrentWeather()
                    showWeatherConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "cloud.sun.fill")
                        Text("Push Weather")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)

                }
                .disabled(!bleManager.isConnected && !isPreview)
                .buttonStyle(.borderedProminent)
                .padding(.trailing)
                .alert(
                    WeatherManager.shared.rateLimitCleared()
                        ? "Successfully updated weather!"
                        : "Weather request ignored due to rate limit. Try again later.",
                    isPresented: $showWeatherConfirmation
                ) {
                    // Default action button
                    Button("OK", role: .cancel) {

                    }
                    .tint(.primary)

                }
                .tint(.accent)

            }
        }
        .scrollIndicators(.hidden)
        .mask(
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [.clear, .black],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 20)
                Rectangle().fill(.black)
                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 20)
            }
        )
        .ignoresSafeArea(edges: .leading)
    }
}

#Preview {
    ActionButtons()
}
