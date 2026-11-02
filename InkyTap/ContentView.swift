import SwiftUI

struct ContentView: View {
    @State private var tapCount = 0

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
                .symbolEffect(.bounce, value: tapCount)

            Text("Hello, World!")
                .font(.largeTitle.weight(.bold))

            Text("Welcome to InkyTap")
                .font(.title3)
                .foregroundStyle(.secondary)

            Button {
                tapCount += 1
            } label: {
                Text(tapCount == 0 ? "Tap me" : "Tapped \(tapCount)×")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
