import SwiftUI
import WeftCore

struct LayoutCanvasView: View {
    @ObservedObject var store: DeviceStore
    var boardHeight: CGFloat = 360
    @State private var drag: ScreenLayoutDrag?
    private var screen: MacScreen? { store.screens.first { $0.id == store.layoutDisplayID } }
    private var placements: [ScreenPlacement] { store.placements.filter { $0.displayID == store.layoutDisplayID } }
    private var missingSizes: [DeviceProfile] {
        store.profiles.filter { store.effectiveDisplay($0) == store.layoutDisplayID && $0.screenGeometry?.isValid != true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("屏幕布局").font(.system(size: 16, weight: .semibold))
                if store.screens.count > 1 {
                    Picker("布局屏幕", selection: $store.layoutDisplayID) {
                        ForEach(store.screens) { Text($0.name).tag($0.id) }
                    }.labelsHidden().frame(maxWidth: 190)
                }
                Spacer()
                Button { drag = nil; store.resetLayout() } label: {
                    Label("重置布局", systemImage: "arrow.counterclockwise")
                }.buttonStyle(WeftButtonStyle())
            }
            if let screen {
                GeometryReader { geo in board(screen: screen, size: geo.size) }
                    .frame(height: boardHeight)
                    .background(WeftStyle.canvas, in: RoundedRectangle(cornerRadius: 10))
            }
            ForEach(missingSizes) { device in
                Label("\(device.name)：连接后读取屏幕尺寸", systemImage: "rectangle.dashed")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Label("拖动设备调整屏幕位置", systemImage: "info.circle")
                    .help("拖动设备贴到 Mac 的任一边；绿色接壤线是双向跨屏通道。")
                Spacer(minLength: 0)
                if screen?.estimatedSize == true || placements.contains(where: { $0.seam.remote.estimated }) {
                    Text("屏幕尺寸为估算值").font(.caption2)
                        .help("部分屏幕未提供物理尺寸，当前使用估算大小。")
                }
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(16)
            .background(WeftStyle.canvas, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(WeftStyle.accent.opacity(0.20), lineWidth: 1))
            .onChange(of: store.layoutDisplayID) { _ in drag = nil }
            .onChange(of: placements) { _ in drag = nil }
    }

    private func board(screen: MacScreen, size: CGSize) -> some View {
        let viewport = drag?.viewport ?? ArrangementViewport(size: size, macSize: screen.layoutSize,
            remoteFrames: placements.map { $0.seam.remoteFrame })
        let mac = viewport.rect(CGRect(origin: .zero, size: screen.layoutSize))
        let macInfo = ArrangementScreenInfo(name: "Mac · \(screen.name)", subtitle: dimensions(screen.layoutSize),
            state: store.activeDeviceID == nil ? "当前控制" : "本机", selected: store.selectedID == nil,
            active: store.activeDeviceID == nil, online: true, symbol: "display")
        let entries = [ArrangementBoardEntry(id: "mac", rect: mac, info: macInfo, side: .above, placement: nil)]
            + placements.compactMap { placement -> ArrangementBoardEntry? in
                guard let device = store.profile(placement.deviceID) else { return nil }
                let seam = displayedSeam(placement)
                let info = ArrangementScreenInfo(name: device.name, subtitle: dimensions(seam.remote.size),
                    state: store.activeDeviceID == device.id ? "当前控制" : store.status(device.id).label,
                    selected: store.selectedID == device.id, active: store.activeDeviceID == device.id,
                    online: store.status(device.id).phase == .ready,
                    symbol: device.kind == .tablet ? "ipad" : "iphone")
                return ArrangementBoardEntry(id: device.id, rect: viewport.rect(seam.remoteFrame),
                    info: info, side: seam.direction, placement: placement)
            }
        let labels = ArrangementLabelLayout.place(entries.map {
            ArrangementLabelLayout.Item(id: $0.id, screen: $0.rect, labelSize: $0.info.outsideSize,
                outside: !$0.info.fits(in: $0.rect.size), preferredSide: $0.side)
        }, in: size)
        return ZStack(alignment: .topLeading) {
            Canvas { context, size in
                for x in stride(from: 8.0, to: size.width, by: 18) {
                    for y in stride(from: 8.0, to: size.height, by: 18) {
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(WeftStyle.accent.opacity(0.24)))
                    }
                }
                for entry in entries {
                    guard let label = labels[entry.id] else { continue }
                    let start = ArrangementLabelLayout.anchor(on: entry.rect, toward: CGPoint(x: label.midX, y: label.midY))
                    let end = ArrangementLabelLayout.anchor(on: label, toward: CGPoint(x: entry.rect.midX, y: entry.rect.midY))
                    var line = Path(); line.move(to: start)
                    if abs(end.x - start.x) >= abs(end.y - start.y) {
                        let midX = (start.x + end.x) / 2
                        line.addLine(to: CGPoint(x: midX, y: start.y)); line.addLine(to: CGPoint(x: midX, y: end.y))
                    } else {
                        let midY = (start.y + end.y) / 2
                        line.addLine(to: CGPoint(x: start.x, y: midY)); line.addLine(to: CGPoint(x: end.x, y: midY))
                    }
                    line.addLine(to: end)
                    context.stroke(line, with: .color(WeftStyle.accentText.opacity(entry.info.selected ? 0.7 : 0.35)),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                }
            }.allowsHitTesting(false)
            ForEach(entries) { entry in
                screenTile(entry, outside: labels[entry.id] != nil, viewport: viewport)
                if let label = labels[entry.id] {
                    outsideLabel(entry, frame: label, viewport: viewport).zIndex(4)
                }
            }
            Canvas { context, _ in
                for placement in placements {
                    let seam = displayedSeam(placement)
                    guard seam.hasContact else { continue }
                    let line = seamLine(seam)
                    var path = Path()
                    path.move(to: viewport.point(line.0)); path.addLine(to: viewport.point(line.1))
                    context.stroke(path, with: .color(WeftStyle.accentText), style: StrokeStyle(lineWidth: 4, lineCap: .butt))
                }
            }.allowsHitTesting(false).zIndex(3)
        }.coordinateSpace(name: "screen-arrangement").clipped()
    }

    private func screenTile(_ entry: ArrangementBoardEntry, outside: Bool, viewport: ArrangementViewport) -> some View {
        let tile = ArrangementScreenTile(info: entry.info, detailsInside: !outside)
            .frame(width: entry.rect.width, height: entry.rect.height)
            .position(x: entry.rect.midX, y: entry.rect.midY)
            .onTapGesture { store.select(entry.placement?.deviceID) }
        return Group {
            if let placement = entry.placement {
                tile.gesture(deviceDrag(placement, viewport: viewport))
                    .accessibilityHint("\(entry.side.label)，拖动调整接壤位置")
            } else { tile }
        }.zIndex(drag?.deviceID == entry.id ? 2 : 1)
    }

    private func outsideLabel(_ entry: ArrangementBoardEntry, frame: CGRect, viewport: ArrangementViewport) -> some View {
        let label = ArrangementOutsideLabel(info: entry.info)
            .frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
            .onTapGesture { store.select(entry.placement?.deviceID) }
        return Group {
            if let placement = entry.placement { label.gesture(deviceDrag(placement, viewport: viewport)) }
            else { label }
        }
    }

    private func deviceDrag(_ placement: ScreenPlacement, viewport: ArrangementViewport) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("screen-arrangement"))
            .onChanged { value in updateDrag(placement, translation: value.translation, viewport: viewport) }
            .onEnded { _ in
                if let drag, drag.deviceID == placement.deviceID { store.moveDevice(placement.deviceID, attachment: drag.attachment) }
                drag = nil
            }
    }

    private func updateDrag(_ placement: ScreenPlacement, translation: CGSize, viewport: ArrangementViewport) {
        if drag?.deviceID != placement.deviceID {
            store.select(placement.deviceID)
            drag = ScreenLayoutDrag(deviceID: placement.deviceID, initial: placement.seam,
                attachment: placement.seam.attachment, viewport: viewport)
        }
        guard var current = drag else { return }
        let origin = CGPoint(x: current.initial.remoteFrame.minX + translation.width / current.viewport.scale,
                             y: current.initial.remoteFrame.minY + translation.height / current.viewport.scale)
        if let attachment = ScreenArrangement.snap(origin: origin, macSize: current.initial.macSize,
            remote: current.initial.remote, occupied: placements.filter { $0.deviceID != placement.deviceID }.map { $0.seam.remoteFrame },
            alignmentTolerance: 7 / current.viewport.scale) {
            current.attachment = attachment
            drag = current
        }
    }
    private func displayedSeam(_ placement: ScreenPlacement) -> ScreenSeam {
        guard let drag, drag.deviceID == placement.deviceID else { return placement.seam }
        return ScreenSeam(macSize: drag.initial.macSize, remote: drag.initial.remote, attachment: drag.attachment)
    }
    private func seamLine(_ seam: ScreenSeam) -> (CGPoint, CGPoint) {
        switch seam.direction {
        case .above: return (CGPoint(x: seam.lower, y: 0), CGPoint(x: seam.upper, y: 0))
        case .below: return (CGPoint(x: seam.lower, y: seam.macSize.height), CGPoint(x: seam.upper, y: seam.macSize.height))
        case .left: return (CGPoint(x: 0, y: seam.lower), CGPoint(x: 0, y: seam.upper))
        case .right: return (CGPoint(x: seam.macSize.width, y: seam.lower), CGPoint(x: seam.macSize.width, y: seam.upper))
        }
    }
    private func dimensions(_ size: CGSize) -> String { String(format: "%.1f × %.1f cm", size.width / 10, size.height / 10) }
}

private struct ArrangementBoardEntry: Identifiable {
    let id: String
    let rect: CGRect
    let info: ArrangementScreenInfo
    let side: Direction
    let placement: ScreenPlacement?
}

private struct ScreenLayoutDrag {
    let deviceID: String
    let initial: ScreenSeam
    var attachment: EdgeAttachment
    let viewport: ArrangementViewport
}

private struct ArrangementViewport {
    let scale: Double
    let offset: CGPoint
    init(size: CGSize, macSize: CGSize, remoteFrames: [CGRect]) {
        // Reserve all four sides so a drag never changes the canvas scale or
        // moves an above/left attachment outside the visible area.
        let width = remoteFrames.map(\.width).max() ?? 0
        let height = remoteFrames.map(\.height).max() ?? 0
        let union = CGRect(x: -width, y: -height, width: macSize.width + 2 * width, height: macSize.height + 2 * height)
        scale = max(0.01, min((size.width - 64) / max(1, union.width), (size.height - 48) / max(1, union.height)))
        offset = CGPoint(x: size.width / 2 - union.midX * scale, y: size.height / 2 - union.midY * scale)
    }
    func point(_ point: CGPoint) -> CGPoint { CGPoint(x: offset.x + point.x * scale, y: offset.y + point.y * scale) }
    func rect(_ rect: CGRect) -> CGRect { CGRect(origin: point(rect.origin), size: CGSize(width: rect.width * scale, height: rect.height * scale)) }
}
