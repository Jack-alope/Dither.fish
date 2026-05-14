import SwiftUI

// MARK: - Color Extension
extension Color {
    static let ditherGreen = Color(red: 0.176, green: 0.416, blue: 0.310)
    static let ditherGreenLight = Color(red: 0.176, green: 0.416, blue: 0.310).opacity(0.15)
}

// MARK: - Weight Formatting
func formatWeight(_ grams: Double) -> String {
    if grams >= 1000 {
        let kg = grams / 1000.0
        return String(format: "%.1fkg", kg)
    } else {
        return "\(Int(grams))g"
    }
}

// MARK: - Date Formatting
private let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withFullDate]
    return f
}()

private let displayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .none
    return f
}()

func formatDateString(_ str: String) -> String {
    if let date = isoFormatter.date(from: str) {
        return displayFormatter.string(from: date)
    }
    return str
}

// MARK: - View Extension for Section Headers
extension View {
    func ditherSectionHeader() -> some View {
        self
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}

// MARK: - Weight Badge View
struct WeightBadge: View {
    let grams: Double

    var body: some View {
        Text(formatWeight(grams))
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.ditherGreenLight)
            .foregroundColor(.ditherGreen)
            .clipShape(Capsule())
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(.secondary.opacity(0.5))
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

// MARK: - Error Banner
struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.white)
            Text(message)
                .font(.footnote)
                .foregroundColor(.white)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.85))
        .cornerRadius(10)
        .padding(.horizontal)
    }
}
