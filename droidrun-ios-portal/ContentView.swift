//
//  ContentView.swift
//  droidrun-ios-portal
//
//  Created by Timo Beckmann on 03.06.25.
//

import SwiftUI

struct ContentView: View {
    @State private var tapCount = 0
    @State private var inputText = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "globe")
                        .imageScale(.large)
                        .foregroundStyle(.tint)
                        .accessibilityIdentifier("fixture.icon")

                    Text("Welcome to Droidrun!")
                        .font(.title2)
                        .accessibilityIdentifier("fixture.title")

                    Text("Tap count: \(tapCount)")
                        .accessibilityIdentifier("fixture.tap-count")

                    Button("Increment tap count") {
                        tapCount += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("fixture.increment")

                    TextField("Automation input", text: $inputText)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("fixture.input")

                    Text("Input value: \(inputText)")
                        .accessibilityIdentifier("fixture.input-value")

                    NavigationLink("Open fixture details") {
                        FixtureDetailView()
                    }
                    .accessibilityIdentifier("fixture.open-details")

                    ForEach(1...8, id: \.self) { index in
                        Text("Scroll marker \(index)")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.secondary.opacity(0.08))
                            .accessibilityIdentifier("fixture.scroll-marker-\(index)")
                    }

                    Text("End of fixture")
                        .font(.headline)
                        .accessibilityIdentifier("fixture.end")
                }
                .padding()
            }
            .navigationTitle("Portal Fixture")
        }
    }
}

private struct FixtureDetailView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Fixture details")
                .font(.title2)
                .accessibilityIdentifier("fixture.details-title")
            Text("Back navigation is ready")
                .accessibilityIdentifier("fixture.details-status")
        }
        .navigationTitle("Details")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
