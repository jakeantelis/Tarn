import SwiftUI

/// Capsule shaped segmented control with a sliding highlight.
struct PillPicker<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    let title: (T) -> String
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                let on = item == selection
                Text(title(item))
                    .font(.callout.weight(on ? .semibold : .regular))
                    .foregroundStyle(on ? Color.white : Color.primary.opacity(0.75))
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background {
                        if on { Capsule().fill(.tint).matchedGeometryEffect(id: "pill", in: ns) }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selection = item } }
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.secondary.opacity(0.14)))
    }
}

/// Fully rounded button. Prominent fills with the accent color.
struct CapsuleButtonStyle: ButtonStyle {
    var prominent = false
    var large = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(large ? .title3.weight(.medium) : .callout)
            .padding(.horizontal, large ? 26 : 14)
            .padding(.vertical, large ? 9 : 6)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background { if prominent { Capsule().fill(.tint) } else { Capsule().fill(Color.secondary.opacity(0.18)) } }
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Round icon button.
struct CircleButtonStyle: ButtonStyle {
    var on = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .frame(width: 28, height: 28)
            .foregroundStyle(on ? Color.white : Color.primary.opacity(0.8))
            .background { if on { Circle().fill(.tint) } else { Circle().fill(Color.secondary.opacity(0.18)) } }
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
