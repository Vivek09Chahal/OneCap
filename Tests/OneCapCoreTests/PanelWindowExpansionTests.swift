import Foundation
import Testing

@testable import OneCapCore

@Test @MainActor func openingPanelGrowsWindowWithoutChangingHeightOrLeftEdgeWhenSpaceAllows() {
    let frame = NSRect(x: 80, y: 100, width: 600, height: 680)
    let screen = NSRect(x: 0, y: 25, width: 2560, height: 950)
    let minimum = PanelWindowExpansion.minimumWidthWithPanel
    #expect(minimum == 1600)
    let expanded = PanelWindowExpansion.expandedFrame(frame, minimumWidth: minimum, within: screen)
    #expect(expanded == NSRect(x: 80, y: 100, width: 1600, height: 680))
    #expect(PanelWindowExpansion.expandedFrame(expanded, minimumWidth: minimum, within: screen) == expanded)
}

@Test @MainActor func openingPanelStaysOnScreenAndNeverShrinksAnAlreadyWideWindow() {
    let screen = NSRect(x: -2560, y: 25, width: 2560, height: 950)
    let minimum = PanelWindowExpansion.minimumWidthWithPanel
    let nearEdge = NSRect(x: -650, y: 100, width: 600, height: 680)
    let expanded = PanelWindowExpansion.expandedFrame(nearEdge, minimumWidth: minimum, within: screen)
    #expect(expanded.width == 1600)
    #expect(expanded.maxX == screen.maxX)
    #expect(expanded.origin.y == nearEdge.origin.y)
    #expect(expanded.height == nearEdge.height)
    let wide = NSRect(x: -2560, y: 100, width: 1600, height: 680)
    #expect(PanelWindowExpansion.expandedFrame(wide, minimumWidth: minimum, within: screen) == wide)
    let full = NSRect(x: -2560, y: 100, width: 2560, height: 680)
    #expect(PanelWindowExpansion.expandedFrame(full, minimumWidth: minimum, within: screen) == full)
    #expect(PanelWindowExpansion.expandedFrame(full, minimumWidth: -1, within: screen) == full)
    #expect(PanelWindowExpansion.expandedFrame(nearEdge, minimumWidth: minimum, within: screen, maximumWidth: 650).width == 650)
    let smallScreen = NSRect(x: 0, y: 25, width: 650, height: 900)
    let smallWindow = NSRect(x: 0, y: 100, width: 600, height: 680)
    #expect(PanelWindowExpansion.expandedFrame(smallWindow, minimumWidth: minimum, within: smallScreen).width == 650)
}
