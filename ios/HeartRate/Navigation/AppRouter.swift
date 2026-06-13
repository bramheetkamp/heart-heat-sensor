import Foundation
import SwiftUI

@MainActor
final class AppRouter: ObservableObject {
    @Published var path = NavigationPath()
    @Published var presentedSheet: AppSheet?

    // MARK: - Sheets

    enum AppSheet: Identifiable {
        case onboarding
        case scenarioPicker

        var id: String {
            switch self {
            case .onboarding:      return "onboarding"
            case .scenarioPicker:  return "scenarioPicker"
            }
        }
    }

    // MARK: - Navigation

    /// Push a route onto the navigation stack.
    func navigate(to route: AppRoute) {
        path.append(route)
    }

    /// Parse a URL and navigate to the corresponding route, if recognized.
    func handle(url: URL) {
        guard let route = AppRoute.from(url: url) else { return }
        navigate(to: route)
    }

    /// Pop the top-most route off the stack.
    func goBack() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    /// Remove all routes, returning to the root.
    func popToRoot() {
        path = NavigationPath()
    }
}
