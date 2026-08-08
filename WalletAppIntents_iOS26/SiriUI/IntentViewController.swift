import IntentsUI
import SwiftUI

// MARK: - SiriUI Intent View Controller
// This controller bridges legacy INIntent UI with modern App Intents.
// For iOS 26, App Intents use ShowsSnippetView for SwiftUI-based Siri UI.
// This file provides a fallback for complex custom layouts or legacy intent support.

class IntentViewController: UIViewController, INUIHostedViewControlling {

    func configureView(
        for parameters: Set<INParameter>,
        of interaction: INInteraction,
        interactiveBehavior: INUIInteractiveBehavior,
        context: INUIHostedViewContext,
        completion: @escaping (Bool, Set<INParameter>, CGSize) -> Void
    ) {
        // Modern App Intents render SwiftUI snippets directly.
        // Use this controller only for advanced custom UI not supported by snippets.
        completion(true, parameters, self.desiredSize)
    }

    var desiredSize: CGSize {
        guard let context = self.extensionContext else {
            return CGSize(width: 320, height: 150)
        }
        return context.hostedViewMaximumAllowedSize
    }
}
