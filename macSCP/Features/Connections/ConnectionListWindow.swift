//
//  ConnectionListWindow.swift
//  macSCP
//
//  Window wrapper for the main connection list. Holds the view model in
//  @State so SwiftUI re-evaluating the App body (e.g. on menu-command focus
//  changes) reuses the same view model instead of recreating it from scratch
//  and resetting the loading state.
//

import SwiftUI
import SwiftData

struct ConnectionListWindow: View {
    @State private var viewModel: ConnectionListViewModel?

    var body: some View {
        Group {
            if let viewModel {
                ConnectionListView(viewModel: viewModel)
            } else {
                LoadingView(message: "Initializing...")
                    .task {
                        viewModel = DependencyContainer.shared.makeConnectionListViewModel()
                    }
            }
        }
        .appLockOverlay()
    }
}

// MARK: - Preview
#Preview {
    ConnectionListWindow()
        .modelContainer(try! ModelContainer(
            for: ConnectionEntity.self, FolderEntity.self, BookmarkEntity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        ))
}
