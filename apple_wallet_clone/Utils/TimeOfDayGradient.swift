import SwiftUI

struct TimeOfDayGradient {
    static func gradient(for date: Date = Date()) -> LinearGradient {
        let hour = Calendar.current.component(.hour, from: date)

        switch hour {
        case 5..<8:
            // Dawn
            return LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.6, blue: 0.3),
                    Color(red: 0.9, green: 0.4, blue: 0.5),
                    Color(red: 0.3, green: 0.2, blue: 0.5)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 8..<12:
            // Morning
            return LinearGradient(
                colors: [
                    Color(red: 0.4, green: 0.7, blue: 1.0),
                    Color(red: 0.6, green: 0.9, blue: 1.0),
                    Color(red: 0.8, green: 0.95, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 12..<17:
            // Afternoon
            return LinearGradient(
                colors: [
                    Color(red: 0.2, green: 0.5, blue: 0.9),
                    Color(red: 0.4, green: 0.7, blue: 1.0),
                    Color(red: 0.6, green: 0.85, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 17..<20:
            // Sunset
            return LinearGradient(
                colors: [
                    Color(red: 0.9, green: 0.3, blue: 0.2),
                    Color(red: 0.8, green: 0.4, blue: 0.3),
                    Color(red: 0.3, green: 0.2, blue: 0.4)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 20..<23:
            // Evening
            return LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.3),
                    Color(red: 0.2, green: 0.15, blue: 0.4),
                    Color(red: 0.3, green: 0.2, blue: 0.5)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            // Night
            return LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.1, green: 0.08, blue: 0.2),
                    Color(red: 0.15, green: 0.1, blue: 0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    static func currentGradient() -> some View {
        TimeOfDayGradient.gradient()
            .ignoresSafeArea()
    }
}

struct TimeOfDayBackground: View {
    @State private var currentTime = Date()
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        TimeOfDayGradient.gradient(for: currentTime)
            .ignoresSafeArea()
            .onReceive(timer) { input in
                currentTime = input
            }
    }
}
