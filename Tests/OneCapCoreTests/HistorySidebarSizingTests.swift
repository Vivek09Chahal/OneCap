import Foundation
import Testing

@testable import OneCapCore

@Test func historySidebarStartsCompactAndGrowsContinuouslyWithWindow() {
    #expect(HistorySidebarSizing.width(in: HistorySidebarSizing.referenceWidth, fraction: nil) == 202)
    let widths = stride(from: CGFloat(1000), through: 1600, by: 10).map {
        HistorySidebarSizing.width(in: $0, fraction: 0.202)
    }
    #expect(abs(widths.first! - 202) < 0.01)
    for (previous, next) in zip(widths, widths.dropFirst()) {
        #expect(abs(next - previous - 2.02) < 0.01)
    }
}

@Test func historySidebarDefaultSizingDoesNotDependOnTransientFirstLayout() {
    #expect(HistorySidebarSizing.width(in: 0, fraction: nil) == 0)
    #expect(HistorySidebarSizing.width(in: 300, fraction: nil) == 0)
    #expect(HistorySidebarSizing.width(in: 600, fraction: nil) == 196)
    #expect(HistorySidebarSizing.width(in: 1134, fraction: nil) == 202)
    #expect(abs(HistorySidebarSizing.width(in: 1500, fraction: nil) - 202 * 1500 / 1134) < 0.01)
}

@Test func historySidebarRespectsBoundsAndKeepsDraggedWidthProportional() {
    #expect(HistorySidebarSizing.width(in: 800, fraction: 0.202) == 196)
    #expect(HistorySidebarSizing.width(in: 2400, fraction: 0.202) == 340)
    let dragged = HistorySidebarSizing.clampedWidth(280, in: 1200)
    #expect(HistorySidebarSizing.width(in: 1200, fraction: dragged / 1200) == 280)
    #expect(abs(HistorySidebarSizing.width(in: 1320, fraction: dragged / 1200) - 308) < 0.01)
    #expect(HistorySidebarSizing.clampedWidth(300, in: 550) == 149)
}
