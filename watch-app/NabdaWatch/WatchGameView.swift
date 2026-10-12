import SwiftUI

struct WatchGameView: View {
    @StateObject private var game = NabdaGame()
    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            VStack(spacing: 2) {
                HStack {
                    Text("⚡ \(game.combo)")
                    Spacer()
                    Text("\(game.score)")
                        .fontWeight(.bold)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                RingView(angle: game.angle, target: game.target, arc: game.arc)
                    .padding(.vertical, 2)

                Text(hearts)
                    .font(.caption)
                    .foregroundStyle(.pink)

                Text(game.feedback)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .id(game.feedbackID)
                    .frame(height: 14)
            }
            .padding(.horizontal, 6)

            if game.phase == .ready {
                VStack(spacing: 6) {
                    Text("نبضة").font(.headline)
                    Text("اضغط عندما تصل الكرة إلى الأزرق أو الأبيض")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                    Button("ابدأ") { game.start() }
                        .tint(.cyan)
                }
                .padding()
                .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
            } else if game.phase == .over {
                VStack(spacing: 6) {
                    Text(game.hits == 0 ? "حاول مرة أخرى" : "انتهت الجولة")
                        .font(.headline)
                    Text("النتيجة \(game.score)")
                        .font(.caption)
                    Button("جولة جديدة") { game.start() }
                        .tint(.cyan)
                }
                .padding()
                .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .contentShape(Rectangle())
        .onTapGesture {
            game.press()
        }
        .onReceive(timer) { now in
            game.tick(now: now)
        }
    }

    private var hearts: String {
        let alive = max(0, game.lives)
        let lost = max(0, Rules.startingLives - alive)
        return String(repeating: "♥", count: alive) + String(repeating: "♡", count: lost)
    }
}

struct RingView: View {
    let angle: Double
    let target: Double
    let arc: Double

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 8

            func point(_ degrees: Double, _ r: CGFloat) -> CGPoint {
                let a = degrees * .pi / 180
                return CGPoint(x: center.x + CGFloat(cos(a)) * r, y: center.y + CGFloat(sin(a)) * r)
            }

            func arcPath(from start: Double, to end: Double, _ r: CGFloat) -> Path {
                var path = Path()
                let steps = max(2, Int(abs(end - start)))
                for i in 0...steps {
                    let degrees = start + (end - start) * Double(i) / Double(steps)
                    let p = point(degrees, r)
                    if i == 0 {
                        path.move(to: p)
                    } else {
                        path.addLine(to: p)
                    }
                }
                return path
            }

            // Track
            context.stroke(arcPath(from: 0, to: 360, radius), with: .color(.white.opacity(0.12)), lineWidth: 3)

            // Blue success zone
            let blue = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [Color(red: 0.24, green: 0.91, blue: 1.0), Color(red: 0.61, green: 0.42, blue: 1.0)]),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: size.height)
            )
            context.stroke(arcPath(from: target - arc, to: target + arc, radius), with: blue,
                           style: StrokeStyle(lineWidth: 9, lineCap: .round))

            // White perfect zone
            let perfectWidth = arc * Rules.perfectRatio
            context.stroke(arcPath(from: target - perfectWidth, to: target + perfectWidth, radius),
                           with: .color(.white), style: StrokeStyle(lineWidth: 4, lineCap: .round))

            // Ball
            let ball = point(angle, radius)
            context.fill(Path(ellipseIn: CGRect(x: ball.x - 5, y: ball.y - 5, width: 10, height: 10)),
                         with: .color(.white))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
