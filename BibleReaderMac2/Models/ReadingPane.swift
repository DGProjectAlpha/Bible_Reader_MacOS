import Foundation

enum SplitDirection {
    case horizontal
    case vertical
}

struct ReadingPane: Identifiable {
    let id: UUID
    var location: BibleLocation
    var splitDirection: SplitDirection
}
