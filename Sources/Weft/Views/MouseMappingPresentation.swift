import WeftCore

extension MouseMappingButton {
    var title: String {
        switch self {
        case .left: return "左键"
        case .right: return "右键"
        case .middle: return "中键"
        case .back: return "侧键 4"
        case .forward: return "侧键 5"
        }
    }
    var subtitle: String {
        switch self {
        case .left: return "主按键"
        case .right: return "辅助按键"
        case .middle: return "滚轮按下"
        case .back: return "拇指后键"
        case .forward: return "拇指前键"
        }
    }
    var icon: String {
        switch self {
        case .left: return "cursorarrow"
        case .right: return "cursorarrow.click.2"
        case .middle: return "computermouse"
        case .back: return "arrow.left"
        case .forward: return "arrow.right"
        }
    }
    var originalTitle: String {
        switch self {
        case .left: return "左键单击"
        case .right: return "右键单击"
        case .middle: return "中键单击"
        case .back: return "原始侧键 4"
        case .forward: return "原始侧键 5"
        }
    }
}

extension MouseMappingAction {
    static var deviceFunctions: [Self] { [.back, .home, .recents, .volumeUp, .volumeDown] }

    func title(for button: MouseMappingButton) -> String {
        switch self {
        case .original: return button.originalTitle
        case .back: return "返回"
        case .home: return "主屏幕"
        case .recents: return "最近任务"
        case .volumeUp: return "音量增加"
        case .volumeDown: return "音量减小"
        }
    }

    func icon(for button: MouseMappingButton) -> String {
        switch self {
        case .original: return button.icon
        case .back: return "arrow.left"
        case .home: return "house"
        case .recents: return "square.on.square"
        case .volumeUp: return "speaker.plus"
        case .volumeDown: return "speaker.minus"
        }
    }
}
