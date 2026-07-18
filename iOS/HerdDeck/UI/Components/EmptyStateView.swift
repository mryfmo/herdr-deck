import SwiftUI

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}
