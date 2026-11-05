import SwiftUI

/// 完了した瞬間に出す、チェックが描かれるアニメーションとひとこと
struct CelebrationView: View {

    let message: String

    /// 分けたタスクが全部終わったときなど、大きい区切りだけ紙吹雪を出す
    let showsConfetti: Bool

    @State private var progress: CGFloat = 0
    @State private var isVisible = false

    var body: some View {
        ZStack {
            if showsConfetti {
                ConfettiView()
            }

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(.green.opacity(0.15))
                        .frame(width: 88, height: 88)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.green, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 88, height: 88)

                    CheckmarkShape()
                        .trim(from: 0, to: progress)
                        .stroke(.green, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                        .frame(width: 38, height: 30)
                }

                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .scaleEffect(isVisible ? 1 : 0.85)
            .opacity(isVisible ? 1 : 0)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                isVisible = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                progress = 1
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width * 0.38, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// 上から舞い落ちる紙吹雪
private struct ConfettiView: View {

    private struct Piece: Identifiable {
        let id: Int
        let x: CGFloat
        let drift: CGFloat
        let rotation: Double
        let color: Color
        let delay: Double
    }

    private let pieces: [Piece] = (0..<36).map { index in
        Piece(
            id: index,
            x: .random(in: 0...1),
            drift: .random(in: -40...40),
            rotation: .random(in: 180...720),
            color: [.green, .blue, .orange, .pink, .yellow, .purple][index % 6],
            delay: .random(in: 0...0.3)
        )
    }

    @State private var isFalling = false

    var body: some View {
        GeometryReader { proxy in
            ForEach(pieces) { piece in
                RoundedRectangle(cornerRadius: 2)
                    .fill(piece.color)
                    .frame(width: 8, height: 12)
                    .rotationEffect(.degrees(isFalling ? piece.rotation : 0))
                    .position(
                        x: piece.x * proxy.size.width + (isFalling ? piece.drift : 0),
                        y: isFalling ? proxy.size.height * 0.9 : -20
                    )
                    .opacity(isFalling ? 0 : 1)
                    .animation(.easeIn(duration: 1.4).delay(piece.delay), value: isFalling)
            }
        }
        .onAppear {
            isFalling = true
        }
    }
}

#Preview {
    CelebrationView(message: "「発表資料を作る」が全部終わりました", showsConfetti: true)
}
