import SwiftUI
import UIKit

/// A pan that reports how many fingers are down, which SwiftUI's drag doesn't: one finger moves
/// the map and, in 3D, two tilt it. Works alongside the pinch, twist and taps.
struct MapPanGesture: UIGestureRecognizerRepresentable {
    let onChange: (UIPanGestureRecognizer) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 2
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        onChange(recognizer)
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> MapGestureCoordinator { MapGestureCoordinator() }
}

/// A pinch that reports the point between the fingers in the view's own coordinates.
struct MapPinchGesture: UIGestureRecognizerRepresentable {
    let onChange: (UIPinchGestureRecognizer, CGPoint) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPinchGestureRecognizer {
        let recognizer = UIPinchGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPinchGestureRecognizer, context: Context) {
        onChange(recognizer, context.converter.localLocation)
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> MapGestureCoordinator { MapGestureCoordinator() }
}

/// A two-finger twist, for turning the 3D map.
struct MapRotateGesture: UIGestureRecognizerRepresentable {
    let onChange: (UIRotationGestureRecognizer) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIRotationGestureRecognizer {
        let recognizer = UIRotationGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIRotationGestureRecognizer, context: Context) {
        onChange(recognizer)
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> MapGestureCoordinator { MapGestureCoordinator() }
}

/// Lets the map's pan, pinch and twist run together.
final class MapGestureCoordinator: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
