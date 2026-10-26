import AppKit
import WeftCore

extension KeyboardKeyCombination {
    var keyCaps: [String] {
        var result: [String] = []
        if modifiers.contains(.control) { result.append("⌃") }
        if modifiers.contains(.option) { result.append("⌥") }
        if modifiers.contains(.shift) { result.append("⇧") }
        if modifiers.contains(.command) { result.append("⌘") }
        return result + [keyLabel]
    }

    var displayTitle: String { keyCaps.joined(separator: " ") }

    init(event: NSEvent) {
        var modifiers: KeyboardModifiers = []
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        let special: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "空格", 51: "⌫", 53: "Esc", 57: "⇪", 65: ".", 67: "*", 69: "+",
            71: "Clear", 75: "/", 76: "Enter", 78: "−", 81: "=", 82: "0", 83: "1", 84: "2",
            85: "3", 86: "4", 87: "5", 88: "6", 89: "7", 91: "8", 92: "9",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13",
            106: "F16", 107: "F14", 109: "F10", 111: "F12", 113: "F15", 114: "Help", 115: "Home",
            116: "Page Up", 117: "⌦", 118: "F4", 119: "End", 120: "F2", 121: "Page Down", 122: "F1",
            123: "←", 124: "→", 125: "↓", 126: "↑", 64: "F17", 79: "F18", 80: "F19", 90: "F20"
        ]
        let characters = event.characters(byApplyingModifiers: []) ?? ""
        let label = special[event.keyCode] ?? (characters.isEmpty ? "按键 \(event.keyCode)" : characters.uppercased())
        self.init(keyCode: event.keyCode, modifiers: modifiers, keyLabel: label)
    }
}

enum KeyboardActionGroup: String, CaseIterable, Identifiable {
    case keyboard = "按键"
    case pointer = "点击与滚动"
    case navigation = "系统导航"
    case direction = "方向与翻页"
    case media = "音量与媒体"
    case device = "屏幕与设备"
    var id: Self { self }
}

extension KeyboardMappingAction {
    var title: String { presentation.title }
    var detail: String { presentation.detail }
    var icon: String { presentation.icon }
    var group: KeyboardActionGroup { presentation.group }

    private var presentation: (title: String, detail: String, icon: String, group: KeyboardActionGroup) {
        switch self {
        case .key: return ("发送按键 / 组合键", "直接录入要发送的单键或组合键", "keyboard", .keyboard)
        case .disabled: return ("禁用此按键", "拦截此按键，不发送到设备", "nosign", .keyboard)
        case .click: return ("单击", "在当前光标位置单击左键", "cursorarrow.click", .pointer)
        case .doubleClick: return ("双击", "在当前光标位置双击左键", "cursorarrow.click.2", .pointer)
        case .longClick: return ("长按", "在当前光标位置长按左键", "hand.tap", .pointer)
        case .rightClick: return ("右键单击", "在当前光标位置单击右键", "computermouse", .pointer)
        case .middleClick: return ("中键单击", "在当前光标位置按下鼠标中键", "computermouse", .pointer)
        case .scrollUp: return ("向上滚动", "在当前光标处滚动，按住可连续滚动", "arrow.up", .pointer)
        case .scrollDown: return ("向下滚动", "在当前光标处滚动，按住可连续滚动", "arrow.down", .pointer)
        case .scrollLeft: return ("向左滚动", "水平滚动，按住可连续滚动", "arrow.left", .pointer)
        case .scrollRight: return ("向右滚动", "水平滚动，按住可连续滚动", "arrow.right", .pointer)
        case .back: return ("返回", "执行 Android 返回操作", "arrow.uturn.backward", .navigation)
        case .home: return ("桌面", "返回 Android 主屏幕", "house", .navigation)
        case .recents: return ("最近任务", "查看最近使用的应用", "square.on.square", .navigation)
        case .forward: return ("前进", "在支持的应用中前进", "arrow.right", .navigation)
        case .notifications: return ("通知栏", "展开 Android 通知栏", "bell", .navigation)
        case .quickSettings: return ("快捷设置", "展开快捷设置面板", "slider.horizontal.3", .navigation)
        case .collapsePanels: return ("收起面板", "收起通知栏和快捷设置", "chevron.up", .navigation)
        case .settings: return ("系统设置", "打开 Android 系统设置", "gearshape", .navigation)
        case .dpadUp: return ("方向上", "向上移动焦点，按住可连续移动", "arrow.up.square", .direction)
        case .dpadDown: return ("方向下", "向下移动焦点，按住可连续移动", "arrow.down.square", .direction)
        case .dpadLeft: return ("方向左", "向左移动焦点，按住可连续移动", "arrow.left.square", .direction)
        case .dpadRight: return ("方向右", "向右移动焦点，按住可连续移动", "arrow.right.square", .direction)
        case .dpadCenter: return ("确认", "确认当前方向键选中的项目", "checkmark.square", .direction)
        case .pageUp: return ("向上翻页", "发送 Page Up，按住可连续翻页", "arrow.up.doc", .direction)
        case .pageDown: return ("向下翻页", "发送 Page Down，按住可连续翻页", "arrow.down.doc", .direction)
        case .volumeUp: return ("音量增加", "调高设备音量，按住可连续调整", "speaker.plus", .media)
        case .volumeDown: return ("音量减小", "调低设备音量，按住可连续调整", "speaker.minus", .media)
        case .mute: return ("静音", "切换设备静音状态", "speaker.slash", .media)
        case .playPause: return ("播放 / 暂停", "切换当前媒体的播放状态", "playpause", .media)
        case .nextTrack: return ("下一首", "切换到下一个媒体项目", "forward.end", .media)
        case .previousTrack: return ("上一首", "切换到上一个媒体项目", "backward.end", .media)
        case .mediaStop: return ("停止播放", "停止当前媒体播放", "stop", .media)
        case .screenshot: return ("屏幕截图", "截取 Android 当前屏幕", "camera.viewfinder", .device)
        case .power: return ("电源键", "切换屏幕亮灭状态", "power", .device)
        case .wake: return ("唤醒屏幕", "唤醒已熄灭的屏幕", "sun.max", .device)
        case .sleep: return ("熄灭屏幕", "让 Android 屏幕进入休眠", "moon", .device)
        case .brightnessUp: return ("亮度增加", "提高屏幕亮度，按住可连续调整", "sun.max", .device)
        case .brightnessDown: return ("亮度减小", "降低屏幕亮度，按住可连续调整", "sun.min", .device)
        case .camera: return ("打开相机", "请求打开设备的相机", "camera", .device)
        case .search: return ("搜索", "执行当前应用或系统搜索", "magnifyingglass", .device)
        case .assistant: return ("语音助手", "打开设备默认的语音助手", "mic", .device)
        case .menu: return ("菜单键", "打开支持菜单键的应用菜单", "line.3.horizontal", .device)
        }
    }
}

extension KeyboardMappingTarget {
    var title: String { action == .key ? shortcut?.displayTitle ?? "选择操作" : action.title }
}
