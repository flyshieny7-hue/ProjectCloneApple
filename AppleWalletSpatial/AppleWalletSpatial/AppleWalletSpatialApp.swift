//
//  AppleWalletSpatialApp.swift
//  AppleWalletSpatial
//
//  App Entry Point — поддержка iPhone и Vision Pro
//

import SwiftUI
import RealityKit
import RealityKitContent

@main
@available(iOS 26.0, visionOS 2.0, *)
struct AppleWalletSpatialApp: App {

    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }
        .defaultSize(width: 800, height: 600)

        #if os(visionOS)
        // Immersive Space for Vision Pro
        ImmersiveSpace(id: "WalletSpace") {
            SpatialWalletSpace()
                .environment(appModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed, .progressive, .full)
        #endif
    }
}

// MARK: - App Model
@Observable
@available(iOS 26.0, visionOS 2.0, *)
class AppModel {
    var isImmersiveSpaceOpen: Bool = false
    var selectedCard: WalletCard?
    var currentTransaction: Transaction?
    var showTransactionFlow: Bool = false

    func openWalletSpace() {
        #if os(visionOS)
        // Open immersive space
        #endif
        isImmersiveSpaceOpen = true
    }

    func closeWalletSpace() {
        isImmersiveSpaceOpen = false
    }
}

// MARK: - Content View
@available(iOS 26.0, visionOS 2.0, *)
struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            #if os(visionOS)
            VisionContentView()
            #else
            iOSContentView()
            #endif
        }
    }
}

// MARK: - Vision Pro Content View
@available(iOS 26.0, visionOS 2.0, *)
struct VisionContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "wallet.pass.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)

                    Text("Apple Wallet Spatial")
                        .font(.system(size: 32, weight: .bold, design: .rounded))

                    Text("Experience your wallet in 3D space")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }

                // Card preview
                SpatialCardView(
                    cardType: .titaniumElite,
                    cardNumber: "4532123456789012",
                    cardHolder: "JOHN DOE",
                    expiryDate: "12/28",
                    balance: 15420.50,
                    currency: "$"
                )
                .frame(depth: 50)

                // Actions
                VStack(spacing: 16) {
                    Button {
                        Task {
                            await openImmersiveSpace(id: "WalletSpace")
                        }
                    } label: {
                        Label("Enter Spatial Wallet", systemImage: "visionpro")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        // Show transaction flow
                    } label: {
                        Label("New Transaction", systemImage: "arrow.left.arrow.right")
                            .font(.headline)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Spacer()
            }
            .padding(40)
            .navigationTitle("Wallet")
        }
    }
}

// MARK: - iOS Content View
@available(iOS 26.0, visionOS 2.0, *)
struct iOSContentView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showWallet = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.9),
                        Color(red: 0.05, green: 0.05, blue: 0.1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "wallet.pass.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.blue)

                        Text("Apple Wallet")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 40)

                    // Quick stats
                    HStack(spacing: 20) {
                        StatCard(title: "Cards", value: "4", icon: "creditcard.fill")
                        StatCard(title: "Balance", value: "$28,671", icon: "dollarsign.circle.fill")
                    }
                    .padding(.horizontal, 20)

                    // Featured card
                    SpatialCardView(
                        cardType: .titaniumElite,
                        cardNumber: "4532123456789012",
                        cardHolder: "JOHN DOE",
                        expiryDate: "12/28",
                        balance: 15420.50,
                        currency: "$"
                    )
                    .shadow(color: .white.opacity(0.1), radius: 20)

                    // Action buttons
                    VStack(spacing: 12) {
                        NavigationLink(destination: SpatialWalletSpace()) {
                            HStack {
                                Image(systemName: "rectangle.stack.fill")
                                Text("View All Cards")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }

                        Button {
                            // Show transaction
                        } label: {
                            HStack {
                                Image(systemName: "arrow.left.arrow.right")
                                Text("Send Money")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }

                        Button {
                            // Add card
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add New Card")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)

                    Spacer()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Stat Card
@available(iOS 26.0, visionOS 2.0, *)
struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Preview
@available(iOS 26.0, visionOS 2.0, *)
#Preview {
    ContentView()
        .environment(AppModel())
}
