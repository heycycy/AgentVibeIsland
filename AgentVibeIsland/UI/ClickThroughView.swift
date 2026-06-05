import AppKit

/// An NSView that passes mouse clicks through transparent areas.
/// Only subviews that are hit-testable receive clicks; the empty
/// transparent background lets clicks fall through to windows behind.
final class ClickThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` is in superview's coordinate system.
        // Bail if outside our frame.
        if isHidden || !NSMouseInRect(point, frame, isFlipped) {
            return nil
        }
        // Convert to our own coordinate system (subview.hitTest expects
        // the point in the subview's superview coordinate system = ours).
        let localPoint = convert(point, from: superview)
        for subview in subviews.reversed() {
            if let hit = subview.hitTest(localPoint) {
                return hit
            }
        }
        // No subview claimed the click — pass through to windows behind.
        return nil
    }
}
