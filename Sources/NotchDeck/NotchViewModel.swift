import SwiftUI

/// UI state for the notch panel, shared between AppKit (window sizing) and SwiftUI (drawing).
final class NotchViewModel: ObservableObject {
    @Published var isExpanded = false
    /// Content visibility is sequenced separately from the shape animation so
    /// nothing is ever drawn outside the black while the shape is moving.
    @Published var showExpandedContent = false
    @Published var showCollapsedContent = true
    @Published var isPinned = false
    @Published var selectedTab: NotchTab = .notes
    @Published var showingSettings = false
    @Published var geometry: NotchGeometry

    /// Extra length on each side of the notch when collapsed (for the live indicators).
    @Published var collapsedWingWidth: CGFloat = 0

    static let expandedSize = CGSize(width: 520, height: 330)
    static let earRadius: CGFloat = 8
    static let bottomRadius: CGFloat = 18

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    var edge: NotchEdge { geometry.edge }

    var collapsedSize: CGSize {
        switch edge {
        case .top:
            return CGSize(width: geometry.notchWidth + collapsedWingWidth * 2 + NotchViewModel.earRadius * 2,
                          height: geometry.notchHeight)
        case .left, .right:
            return CGSize(width: NotchGeometry.sideThickness,
                          height: NotchGeometry.sideBaseLength + collapsedWingWidth * 2 + NotchViewModel.earRadius * 2)
        }
    }

    var expandedSize: CGSize {
        switch edge {
        case .top:
            // Each wing beside the camera needs ~170pt for the tab strip / controls.
            return CGSize(width: max(NotchViewModel.expandedSize.width, geometry.notchWidth + 2 * 176),
                          height: NotchViewModel.expandedSize.height)
        case .left, .right:
            return NotchViewModel.expandedSize
        }
    }

    var currentSize: CGSize { isExpanded ? expandedSize : collapsedSize }

    /// Where the shape hugs inside the window.
    var alignment: Alignment {
        switch edge {
        case .top: return .top
        case .left: return .leading
        case .right: return .trailing
        }
    }
}
