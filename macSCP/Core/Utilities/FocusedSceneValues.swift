//
//  FocusedSceneValues.swift
//  macSCP
//
//  Focused-value plumbing so app-menu shortcuts (⌘R, ⌘N, ⌘I, …) route to the
//  key window's view model. Each window scene publishes its own view model;
//  menu items resolve the value from the focused scene and disable themselves
//  when a window type doesn't provide one.
//

import SwiftUI

// MARK: - Keys

private struct BrowserViewModelKey: FocusedValueKey {
    typealias Value = FileBrowserViewModel
}

private struct ConnectionListViewModelKey: FocusedValueKey {
    typealias Value = ConnectionListViewModel
}

extension FocusedValues {
    var browserViewModel: FileBrowserViewModel? {
        get { self[BrowserViewModelKey.self] }
        set { self[BrowserViewModelKey.self] = newValue }
    }

    var connectionListViewModel: ConnectionListViewModel? {
        get { self[ConnectionListViewModelKey.self] }
        set { self[ConnectionListViewModelKey.self] = newValue }
    }
}

// MARK: - Hashable Conformances

// `.focusedSceneValue(_:_)` requires Hashable values; both view models are
// reference types, so identity semantics are the right equality.
extension FileBrowserViewModel: Hashable {
    nonisolated static func == (lhs: FileBrowserViewModel, rhs: FileBrowserViewModel) -> Bool {
        lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

extension ConnectionListViewModel: Hashable {
    nonisolated static func == (lhs: ConnectionListViewModel, rhs: ConnectionListViewModel) -> Bool {
        lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
