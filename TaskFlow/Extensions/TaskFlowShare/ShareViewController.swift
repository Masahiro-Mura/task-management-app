import Social
import UIKit
import UniformTypeIdentifiers

/// 共有シートから TaskFlow に足す
///
/// 共有されたページ名やテキストを、タスク名の案として入力欄に入れる。書き直してから「追加」できる。
/// ここでは受け箱（`ShareInbox`）に入れるだけで、タスクにするのは次にアプリを開いたとき。
final class ShareViewController: SLComposeServiceViewController {

    private var sharedURL: URL?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "TaskFlow に追加"
        placeholder = "タスク名（例：明日までに読む 15分）"
        navigationController?.navigationBar.topItem?.rightBarButtonItem?.title = "追加"

        let pageTitle = contentText
        loadSharedURL { [weak self] url in
            guard let self else {
                return
            }
            self.sharedURL = url

            // 共有されたのがページなら「〇〇」を読む、にしておく
            let suggestion = ShareInbox.suggestedTitle(pageTitle: pageTitle, url: url)
            if !suggestion.isEmpty {
                self.textView.text = suggestion
                self.validateContent()
            }
        }
    }

    override func isContentValid() -> Bool {
        !(contentText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    override func didSelectPost() {
        let text = (contentText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if !text.isEmpty, let defaults = SharedStore.defaults {
            ShareInbox.append(
                ShareInbox.Item(text: text, link: sharedURL, sharedAt: Date()),
                to: defaults
            )
        }

        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    override func configurationItems() -> [Any]! {
        []
    }

    /// 共有されたもののなかから、ページのURLを探す
    private func loadSharedURL(_ completion: @escaping @MainActor (URL?) -> Void) {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }

        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) else {
            completion(nil)
            return
        }

        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            Task { @MainActor in
                completion(url)
            }
        }
    }
}
