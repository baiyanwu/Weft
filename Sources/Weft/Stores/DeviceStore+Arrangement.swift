import AppKit
import WeftCore

extension DeviceStore {
    var placements: [ScreenPlacement] {
        var result: [ScreenPlacement] = []
        for device in profiles {
            guard let geometry = device.screenGeometry, geometry.isValid,
                  let screen = screens.first(where: { $0.id == effectiveDisplay(device) }) else { continue }
            var attachment = ScreenArrangement.attachment(direction: device.direction, offset: device.edgeOffsetMM,
                macSize: screen.layoutSize, remoteSize: geometry.size)
            let desired = ScreenSeam(macSize: screen.layoutSize, remote: geometry, attachment: attachment)
            let occupied = result.filter { $0.displayID == screen.id }.map { $0.seam.remoteFrame }
            if occupied.contains(where: {
                let intersection = desired.remoteFrame.intersection($0)
                return !intersection.isNull && intersection.width > 0.001 && intersection.height > 0.001
            }) {
                guard let available = ScreenArrangement.snap(origin: desired.remoteFrame.origin,
                    macSize: screen.layoutSize, remote: geometry, occupied: occupied) else { continue }
                attachment = available
            }
            result.append(ScreenPlacement(deviceID: device.id, displayID: screen.id,
                seam: ScreenSeam(macSize: screen.layoutSize, remote: geometry, attachment: attachment)))
        }
        return result
    }

    func moveDevice(_ id: String, attachment: EdgeAttachment) {
        update(id) {
            $0.direction = attachment.direction
            $0.edgeOffsetMM = attachment.offset
            $0.displayID = layoutDisplayID
        }
    }

    func receiveScreenGeometry(_ id: String, _ event: [String: Any]) {
        guard let index = profiles.firstIndex(where: { $0.id == id }),
              let width = event["width"] as? Int, let height = event["height"] as? Int,
              let rotation = event["rotation"] as? Int,
              let widthMM = event["layoutWidthMM"] as? NSNumber,
              let heightMM = event["layoutHeightMM"] as? NSNumber else { return }
        let geometry = RemoteScreenGeometry(width: width, height: height, rotation: rotation,
            widthMM: widthMM.doubleValue, heightMM: heightMM.doubleValue,
            estimated: event["estimatedSize"] as? Bool ?? true)
        guard geometry.isValid, geometry != profiles[index].screenGeometry else { return }
        if mouse.activeDeviceID == id { mouse.returnToMac("屏幕尺寸或方向已变化，布局已更新") }
        profiles[index].screenGeometry = geometry
        save(); refreshPortals()
        Log.write("Device geometry: \(id), \(width)x\(height), rotation=\(rotation), size=\(geometry.widthMM)x\(geometry.heightMM)mm, estimated=\(geometry.estimated)")
    }
}
