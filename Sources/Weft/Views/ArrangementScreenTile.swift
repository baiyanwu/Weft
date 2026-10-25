import SwiftUI
import AppKit

struct ArrangementScreenInfo {
    let name: String
    let subtitle: String
    let state: String
    let selected: Bool
    let active: Bool
    let online: Bool
    let symbol: String

    private var textWidth: CGFloat {
        max((name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]).width,
            (subtitle as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width,
            (state as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10)]).width)
    }
    func fits(in size: CGSize) -> Bool { size.width >= textWidth + 24 && size.height >= 78 }
    var outsideSize: CGSize { CGSize(width: min(190, max(144, textWidth + 20)), height: 76) }
    var description: String { "\(name)，\(subtitle)，\(state)" }
}

struct ArrangementScreenTile: View {
    let info: ArrangementScreenInfo
    let detailsInside: Bool
    var body: some View {
        Group {
            if detailsInside {
                VStack(spacing: 6) {
                    Text(info.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(info.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    Text(info.state).font(.system(size: 10)).foregroundStyle(info.active ? WeftStyle.accentText : .secondary).lineLimit(1)
                }.padding(10)
            } else {
                Image(systemName: info.symbol).font(.system(size: 17, weight: .regular))
                    .foregroundStyle(info.active || info.selected ? WeftStyle.accentText : .secondary)
                    .padding(5)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WeftStyle.tile)
            .overlay(Rectangle().fill(WeftStyle.accent.opacity(info.active ? 0.13 : info.selected ? 0.07 : 0)))
            .overlay(Rectangle().strokeBorder(info.selected ? WeftStyle.accentText : WeftStyle.border, lineWidth: info.selected ? 2 : 1))
            .opacity(info.online ? 1 : 0.65).contentShape(Rectangle())
            .accessibilityElement(children: .ignore).accessibilityLabel(info.description)
            .help(info.description)
    }
}

struct ArrangementOutsideLabel: View {
    let info: ArrangementScreenInfo
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(info.name).font(.system(size: 12, weight: .semibold)).lineLimit(2)
            Text(info.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 5) {
                Circle().fill(info.active ? WeftStyle.accentText : info.online ? Color.green : .secondary)
                    .frame(width: 5, height: 5)
                Text(info.state).font(.system(size: 10)).foregroundStyle(info.active ? WeftStyle.accentText : .secondary).lineLimit(1)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 8)
            .background(WeftStyle.tile, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(info.selected ? WeftStyle.accent.opacity(0.65) : WeftStyle.border, lineWidth: 1))
            .help(info.description)
            .accessibilityElement(children: .ignore).accessibilityLabel(info.description)
    }
}
