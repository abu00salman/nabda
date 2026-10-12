import Foundation
import WatchKit

// Same numbers as GAME_CONFIG in index.html (version 2.1.2).
enum Rules {
    static let startingLives = 5
    static let startingSpeed = 110.0
    static let maxSpeed = 420.0
    static let speedStep = 60.0
    static let startingArc = 48.0
    static let minArc = 6.0
    static let arcStep = 9.0
    static let hitsPerLevel = 7
    static let perfectRatio = 0.32
    static let edgeTolerance = 6.0
    static let recoveryHits = 3
    static let recoverySpeedFactor = 0.85
    static let tapDebounce: TimeInterval = 0.08
    static let comboTiers: [(at: Int, mult: Double)] = [(50, 2), (30, 1.6), (20, 1.4), (10, 1.2)]
}

// Angles are in degrees, 0 = right, increasing clockwise on screen (same as the web canvas).
func normalizeAngle(_ a: Double) -> Double {
    let r = a.truncatingRemainder(dividingBy: 360)
    return r < 0 ? r + 360 : r
}

// Signed shortest difference a - b, in (-180, 180].
func angleDifference(_ a: Double, _ b: Double) -> Double {
    let d = normalizeAngle(a - b)
    return d > 180 ? d - 360 : d
}

enum Zone {
    case perfect, great, good, miss
}

func classify(distance d: Double, arc: Double) -> Zone {
    if d <= arc * Rules.perfectRatio { return .perfect }
    if d <= arc { return .great }
    if d <= arc + Rules.edgeTolerance { return .good }
    return .miss
}

@MainActor
final class NabdaGame: ObservableObject {
    enum Phase {
        case ready, playing, over
    }

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var angle: Double = -90
    @Published private(set) var target: Double = 90
    @Published private(set) var arc: Double = Rules.startingArc
    @Published private(set) var lives: Int = Rules.startingLives
    @Published private(set) var score: Int = 0
    @Published private(set) var combo: Int = 0
    @Published private(set) var hits: Int = 0
    @Published private(set) var level: Int = 1
    @Published private(set) var feedback: String = ""
    @Published private(set) var feedbackID: Int = 0

    private var speed = Rules.startingSpeed
    private var recoveryLeft = 0
    private var lastPressAt = Date.distantPast
    private var lastTick: Date?

    func start() {
        angle = -90
        lives = Rules.startingLives
        score = 0
        combo = 0
        hits = 0
        level = 1
        recoveryLeft = 0
        feedback = ""
        lastTick = nil
        applyLevel()
        newTarget()
        phase = .playing
    }

    // Called from the timer. Keeps the ball moving whether or not the user taps.
    func tick(now: Date) {
        guard phase == .playing else {
            lastTick = nil
            return
        }
        if let last = lastTick {
            let dt = min(now.timeIntervalSince(last), 0.05)
            angle = normalizeAngle(angle + speed * dt)
            // Passing the target without a tap: no heart lost, streak kept. Pick a new target silently.
            if angleDifference(angle, target) > arc + Rules.edgeTolerance {
                newTarget()
            }
        }
        lastTick = now
    }

    func press() {
        guard phase == .playing else { return }
        let now = Date()
        guard now.timeIntervalSince(lastPressAt) >= Rules.tapDebounce else { return }
        lastPressAt = now

        switch classify(distance: abs(angleDifference(angle, target)), arc: arc) {
        case .perfect: registerHit(.perfect)
        case .great: registerHit(.great)
        case .good: registerHit(.good)
        case .miss: registerMiss()
        }
    }

    private func registerHit(_ zone: Zone) {
        if zone == .perfect || zone == .great {
            combo += 1
        }
        let multiplier = Rules.comboTiers.first(where: { combo >= $0.at })?.mult ?? 1
        let base: Double
        switch zone {
        case .perfect: base = 100
        case .great: base = 70
        default: base = 40
        }
        score += Int((base * multiplier).rounded())
        hits += 1

        switch zone {
        case .perfect:
            show("مثالي")
            WKInterfaceDevice.current().play(.success)
        case .great:
            show("رائع")
            WKInterfaceDevice.current().play(.click)
        default:
            show("جيد")
            WKInterfaceDevice.current().play(.click)
        }

        if recoveryLeft > 0 {
            recoveryLeft -= 1
            if recoveryLeft == 0 { applyLevel() }
        }
        if hits % Rules.hitsPerLevel == 0 {
            level += 1
            applyLevel()
        }
        newTarget()
    }

    private func registerMiss() {
        combo = 0
        lives -= 1
        show("ضغطت خارج المنطقة")
        WKInterfaceDevice.current().play(.failure)
        if lives <= 0 {
            phase = .over
            return
        }
        recoveryLeft = Rules.recoveryHits
        applyLevel()
        newTarget()
    }

    private func applyLevel() {
        let t = Double(max(0, level - 1)).squareRoot()
        let factor = recoveryLeft > 0 ? Rules.recoverySpeedFactor : 1
        speed = min(Rules.maxSpeed, Rules.startingSpeed + Rules.speedStep * t) * factor
        arc = max(Rules.minArc, Rules.startingArc - Rules.arcStep * t)
    }

    // Always less than 180 degrees ahead of the ball (same rule as the web game).
    private func newTarget() {
        target = normalizeAngle(angle + Double.random(in: 110...170))
    }

    private func show(_ text: String) {
        feedback = text
        feedbackID += 1
    }
}
