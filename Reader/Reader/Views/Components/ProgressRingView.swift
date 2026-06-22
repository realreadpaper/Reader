import SwiftUI

struct ProgressRingView: View {
    let progress: Double
    let lineWidth: CGFloat

    init(progress: Double, lineWidth: CGFloat = 3) {
        self.progress = progress
        self.lineWidth = lineWidth
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: "#D5C8B0"), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color(hex: "#8B7355"), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)
        }
    }
}
