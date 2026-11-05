import SwiftUI

/// 直前の操作の「元に戻す」（`HomeViewModel.undoEntry`）
///
/// どの画面で操作しても、その画面の下に出す。しばらくたつと消える（消えるまでは、別の画面に移っても戻せる）。
struct UndoBanner: View {

    @ObservedObject var viewModel: HomeViewModel

    /// 出しておく時間
    static let duration: Duration = .seconds(8)

    var body: some View {
        Group {
            if let entry = viewModel.undoEntry {
                HStack(spacing: 12) {
                    Text(entry.message)
                        .font(.subheadline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    Spacer(minLength: 0)

                    Button(entry.actionTitle) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.undo()
                        }
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("undoButton")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: entry.id) {
                    try? await Task.sleep(for: Self.duration)
                    if !Task.isCancelled {
                        withAnimation(.easeOut(duration: 0.2)) {
                            viewModel.dismissUndo(entry.id)
                        }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.undoEntry?.id)
    }
}

/// 画面の奥（一覧・編集・設定・シート）でも「元に戻す」を出せるよう、ViewModel を環境で渡す
private struct HomeViewModelKey: EnvironmentKey {
    static let defaultValue: HomeViewModel? = nil
}

extension EnvironmentValues {
    var homeViewModel: HomeViewModel? {
        get { self[HomeViewModelKey.self] }
        set { self[HomeViewModelKey.self] = newValue }
    }
}

/// 環境の ViewModel があれば、画面の下に「元に戻す」を出す（プレビューなど、なければ何もしない）
private struct UndoBannerModifier: ViewModifier {
    @Environment(\.homeViewModel) private var viewModel

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            if let viewModel {
                UndoBanner(viewModel: viewModel)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
    }
}

extension View {
    /// 画面の下に「元に戻す」を出す
    func undoBanner() -> some View {
        modifier(UndoBannerModifier())
    }
}
