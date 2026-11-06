import SwiftUI

/// A white SF Symbol on a rounded colored tile, like System Settings.
struct SettingsIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Header of a Settings page: icon tile, title, one-line summary and an optional control.
struct SettingsHeader<Accessory: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let summary: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: icon, tint: tint, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.bold())
                if !summary.isEmpty {
                    Text(summary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            accessory
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

extension SettingsHeader where Accessory == EmptyView {
    init(icon: String, tint: Color, title: String, summary: String) {
        self.init(icon: icon, tint: tint, title: title, summary: summary) { EmptyView() }
    }
}
