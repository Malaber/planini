import Foundation

public enum WatchListAction: Equatable, Sendable {
    case added(item: GroceryItemRecord)
    case toggled(before: GroceryItemRecord, after: GroceryItemRecord)
    case edited(before: GroceryItemRecord, after: GroceryItemRecord)

    public var undoTitle: String {
        switch self {
        case let .added(item):
            return "Undo add: \(item.name)"
        case let .toggled(_, after):
            return after.checked ? "Undo check: \(after.name)" : "Undo uncheck: \(after.name)"
        case let .edited(_, after):
            return "Undo edit: \(after.name)"
        }
    }

    public var redoTitle: String {
        switch self {
        case let .added(item):
            return "Redo add: \(item.name)"
        case let .toggled(_, after):
            return after.checked ? "Redo check: \(after.name)" : "Redo uncheck: \(after.name)"
        case let .edited(_, after):
            return "Redo edit: \(after.name)"
        }
    }

    public var isNoop: Bool {
        switch self {
        case .added:
            return false
        case let .toggled(before, after):
            return before.checked == after.checked
        case let .edited(before, after):
            return before == after
        }
    }
}

public struct WatchListActionHistory: Equatable, Sendable {
    public private(set) var undoStack: [WatchListAction]
    public private(set) var redoStack: [WatchListAction]
    public let limit: Int

    public init(
        undoStack: [WatchListAction] = [],
        redoStack: [WatchListAction] = [],
        limit: Int = 10
    ) {
        self.undoStack = Array(undoStack.suffix(limit))
        self.redoStack = Array(redoStack.suffix(limit))
        self.limit = limit
    }

    public var canUndo: Bool {
        undoStack.isEmpty == false
    }

    public var canRedo: Bool {
        redoStack.isEmpty == false
    }

    public var undoTitle: String? {
        undoStack.last?.undoTitle
    }

    public var redoTitle: String? {
        redoStack.last?.redoTitle
    }

    public mutating func record(_ action: WatchListAction) {
        guard action.isNoop == false else { return }
        undoStack.append(action)
        trimUndoStack()
        redoStack.removeAll()
    }

    public mutating func popUndo() -> WatchListAction? {
        undoStack.popLast()
    }

    public mutating func restoreUndo(_ action: WatchListAction) {
        undoStack.append(action)
        trimUndoStack()
    }

    public mutating func completeUndo(_ action: WatchListAction) {
        redoStack.append(action)
        trimRedoStack()
    }

    public mutating func popRedo() -> WatchListAction? {
        redoStack.popLast()
    }

    public mutating func restoreRedo(_ action: WatchListAction) {
        redoStack.append(action)
        trimRedoStack()
    }

    public mutating func completeRedo(_ action: WatchListAction) {
        undoStack.append(action)
        trimUndoStack()
    }

    private mutating func trimUndoStack() {
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
    }

    private mutating func trimRedoStack() {
        if redoStack.count > limit {
            redoStack.removeFirst(redoStack.count - limit)
        }
    }
}
