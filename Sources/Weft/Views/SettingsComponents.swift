import SwiftUI

struct PageHeading: View {
    let title: String
    let subtitle: String
    var badge: String? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 27, weight: .bold))
                Text(subtitle).font(.system(size: 14)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let badge {
                Text(badge).font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(WeftStyle.border, lineWidth: 1))
            }
        }.padding(.bottom, 3)
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 17).padding(.vertical, 11)
                .background(WeftStyle.accent.opacity(0.035))
            Divider()
            content.padding(17)
        }.background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(WeftStyle.border, lineWidth: 1))
    }
}

struct PendingBadge: View {
    var body: some View {
        Text("暂未开放").font(.system(size: 10, weight: .medium)).foregroundStyle(WeftStyle.secondaryText)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(Color.secondary.opacity(0.08), in: Capsule())
    }
}

struct KeyCap: View {
    let title: String
    var body: some View {
        Text(title).font(.system(size: 13, weight: .medium, design: .monospaced))
            .frame(minWidth: 23).padding(.horizontal, 10).frame(height: 30)
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(WeftStyle.border, lineWidth: 1))
    }
}

struct PopoverAction: View {
    let title: String
    let icon: String
    var pending = false
    var destructive = false
    var disabled = false
    var action: () -> Void = {}
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon).font(.system(size: 18)).frame(width: 24)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 5)
                if pending { PendingBadge() }
            }.padding(.horizontal, 11).frame(height: 39).contentShape(Rectangle())
                .foregroundStyle(pending || disabled ? Color.secondary : destructive ? .red : .primary)
                .background(hovered && !pending && !disabled ? WeftStyle.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).disabled(pending || disabled)
            .onHover { hovered = $0 }
            .help(pending ? "仅展示入口，功能暂未开放" : title)
    }
}

struct SelectionField: View {
    let title: String
    var expanded = false
    var showsIndicator = true
    var body: some View {
        HStack(spacing: 8) {
            Text(title).lineLimit(1)
            Spacer(minLength: 3)
            if showsIndicator { Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .medium)) }
        }.font(.system(size: 13)).padding(.horizontal, 11).frame(height: 33)
            .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(expanded ? WeftStyle.accent : WeftStyle.border, lineWidth: 1))
            .shadow(color: expanded ? WeftStyle.accent.opacity(0.15) : .clear, radius: 2)
            .contentShape(Rectangle())
    }
}

struct SelectionOptionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon).font(.system(size: 26)).frame(width: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).fontWeight(.medium).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if selected { Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(WeftStyle.accentText) }
            }.padding(.horizontal, 13).frame(height: 60).contentShape(Rectangle())
                .background(selected ? WeftStyle.wash : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
