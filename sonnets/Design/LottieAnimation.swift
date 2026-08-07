import Lottie
import SwiftUI

struct BundledLottieAnimation: UIViewRepresentable {
    let name: String
    var loopMode: LottieLoopMode = .loop

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.clipsToBounds = true

        let animationView = LottieAnimationView(name: name)
        animationView.translatesAutoresizingMaskIntoConstraints = false
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.contentMode = .scaleAspectFit
        animationView.loopMode = loopMode
        animationView.play()
        animationView.accessibilityElementsHidden = true
        container.addSubview(animationView)
        NSLayoutConstraint.activate([
            animationView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            animationView.topAnchor.constraint(equalTo: container.topAnchor),
            animationView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        guard let animationView = container.subviews.first as? LottieAnimationView else { return }
        animationView.loopMode = loopMode
        if !animationView.isAnimationPlaying {
            animationView.play()
        }
    }
}

/// Plays a bundled animation once whenever `trigger` changes, then keeps its
/// final frame visible. This is useful for stateful controls such as favourite.
struct TriggeredLottieAnimation: UIViewRepresentable {
    let name: String
    let trigger: Int
    var restingProgress = 1.0

    final class Coordinator {
        var lastTrigger: Int

        init(lastTrigger: Int) {
            self.lastTrigger = lastTrigger
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(lastTrigger: trigger)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.clipsToBounds = true

        let animationView = LottieAnimationView(name: name)
        animationView.translatesAutoresizingMaskIntoConstraints = false
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.contentMode = .scaleAspectFit
        animationView.loopMode = .playOnce
        animationView.accessibilityElementsHidden = true
        animationView.clipsToBounds = true
        container.addSubview(animationView)
        NSLayoutConstraint.activate([
            animationView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            animationView.topAnchor.constraint(equalTo: container.topAnchor),
            animationView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        if trigger > 0 {
            animationView.play(fromProgress: 0, toProgress: 1, loopMode: .playOnce)
        } else {
            animationView.currentProgress = restingProgress
        }
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        guard let animationView = container.subviews.first as? LottieAnimationView else { return }
        guard context.coordinator.lastTrigger != trigger else { return }
        context.coordinator.lastTrigger = trigger
        animationView.stop()
        animationView.currentProgress = 0
        animationView.play(fromProgress: 0, toProgress: 1, loopMode: .playOnce)
    }
}
