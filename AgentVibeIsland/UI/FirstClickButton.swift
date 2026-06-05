import AppKit

/// An NSButton subclass that accepts mouse clicks on the first click,
/// even when its window is not the key window. Essential for buttons
/// in non-activating panels.
final class FirstClickButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}
