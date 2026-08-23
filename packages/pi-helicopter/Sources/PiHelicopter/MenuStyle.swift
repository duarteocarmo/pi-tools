import AppKit

enum MenuStyle {
    static let width: CGFloat = 300
    static let padding: CGFloat = 14
    static let contentWidth = width - padding * 2
    static let pickerHeight: CGFloat = 38
    static let controlSize = NSControl.ControlSize.small

    static let title = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let section = NSFont.systemFont(ofSize: 12, weight: .semibold)
    static let value = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    static let primary = NSFont.systemFont(ofSize: 10, weight: .semibold)
    static let metadata = NSFont.systemFont(ofSize: 10, weight: .medium)
    static let number = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
    static let caption = NSFont.systemFont(ofSize: 9, weight: .medium)
    static let captionMono = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
}
