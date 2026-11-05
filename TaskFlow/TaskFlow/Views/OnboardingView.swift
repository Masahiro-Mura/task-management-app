import SwiftUI

/// 初めて開いたときの案内。3枚だけで、すぐ使い始められるようにする
struct OnboardingView: View {

    let onFinish: (_ addExamples: Bool) -> Void

    @State private var page = 0

    private struct Page {
        let systemImage: String
        let title: String
        let body: String
        let example: String?
    }

    private let pages: [Page] = [
        Page(
            systemImage: "sparkles",
            title: "開いたら、今やる1つ",
            body: "空き時間・期限・優先度から、今やるタスクを1件だけ選びます。なぜそれなのか、理由も添えます。",
            example: nil
        ),
        Page(
            systemImage: "text.cursor",
            title: "1行で入れるだけ",
            body: "日付・時間・くり返しは、書いたとおりに読み取ります。",
            example: "明日の15時に資料作成 30分\n金曜までにレポート 2時間\n毎週月曜にゴミ出し 5分"
        ),
        Page(
            systemImage: "leaf",
            title: "できなかった日も、責めません",
            body: "やり残しは静かに持ち越し、放っておいたものは冬眠します。気が乗らない日は、軽いものだけにもできます。",
            example: nil
        )
    ]

    private var isLastPage: Bool {
        page == pages.count - 1
    }

    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    pageView(pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 12) {
                if isLastPage {
                    Button {
                        onFinish(false)
                    } label: {
                        Text("始める")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("例を3つ入れて試してみる") {
                        onFinish(true)
                    }
                    .controlSize(.large)
                } else {
                    Button {
                        withAnimation {
                            page += 1
                        }
                    } label: {
                        Text("次へ")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("とばす") {
                        onFinish(false)
                    }
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: 560)
    }

    private func pageView(_ page: Page) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: page.systemImage)
                .font(.system(size: 56))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            Text(page.title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(page.body)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let example = page.example {
                Text(example)
                    .font(.callout)
                    .monospaced()
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel("入力の例：\(example.replacingOccurrences(of: "\n", with: "、"))")
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

#Preview {
    OnboardingView { _ in }
}
