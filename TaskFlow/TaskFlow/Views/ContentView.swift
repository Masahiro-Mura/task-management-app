import SwiftUI

struct ContentView: View {

    @StateObject private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("今やること")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                if let recommendation = viewModel.recommendation {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(recommendation.task.title)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("所要時間：\(recommendation.task.estimatedMinutes)分")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(recommendation.reason)
                            .font(.body)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    ContentUnavailableView(
                        "実行できるタスクがありません",
                        systemImage: "checkmark.circle"
                    )
                }

                Spacer()
            }
            .padding()
            .navigationTitle("TaskFlow")
            .task {
                viewModel.loadRecommendation()
            }
        }
    }
}

#Preview {
    ContentView()
}
