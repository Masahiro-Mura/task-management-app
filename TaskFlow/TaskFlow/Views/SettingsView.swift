import SwiftUI
import UniformTypeIdentifiers

/// 設定。通知は最小限で、アイコンの赤い数字は出さない
struct SettingsView: View {

    @ObservedObject var viewModel: HomeViewModel

    @State private var isImporting = false
    @State private var importMessage: String?

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(version)（\(build)）"
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    "期限が近いときに知らせる",
                    isOn: Binding(
                        get: { viewModel.deadlineNotificationsEnabled },
                        set: { enabled in Task { await viewModel.setDeadlineNotifications(enabled) } }
                    )
                )

                Toggle(
                    "毎日1回「今の1つ」を届ける",
                    isOn: Binding(
                        get: { viewModel.dailyPickEnabled },
                        set: { enabled in Task { await viewModel.setDailyPick(enabled) } }
                    )
                )

                if viewModel.dailyPickEnabled {
                    DatePicker(
                        "届ける時刻",
                        selection: Binding(
                            get: { Self.date(fromMinutes: viewModel.dailyPickMinutes) },
                            set: { viewModel.setDailyPickMinutes(Self.minutes(from: $0)) }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                }
            } header: {
                Text("通知")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("期限の3時間前に1回だけ知らせます。何度も催促はしません。アイコンに赤い数字も出しません。")

                    if viewModel.dailyPickPausedByIgnore {
                        Text("「今の1つ」が続けて開かれなかったので、いったん止めました。また届けてほしくなったら、オンにしてください。")
                            .foregroundStyle(.orange)
                    }

                    if viewModel.notificationPermissionDenied {
                        Text("通知が許可されていません。設定アプリの「通知」から TaskFlow を許可してください。")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                Toggle(
                    "始めたら、ほかの通知も止める",
                    isOn: Binding(
                        get: { viewModel.usesFocusShortcut },
                        set: { viewModel.setUsesFocusShortcut($0) }
                    )
                )

                if viewModel.usesFocusShortcut {
                    DisclosureGroup("ショートカットの作り方") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("1. 「ショートカット」アプリで、新しいショートカットを作り、名前を「\(HomeViewModel.focusStartShortcutName)」にします。")
                            Text("2. 「集中モードを設定」を足し、「おやすみモード」（またはお好きな集中モード）を「オン」「オフにするまで」にします。")
                            Text("3. 最後に「Appを開く」を足して「TaskFlow」を選びます（終わったら自動で戻ってきます）。")
                            Text("4. 同じように「\(HomeViewModel.focusEndShortcutName)」を作り、集中モードを「オフ」にして、TaskFlow を開くようにします。")
                        }
                        .font(.footnote)
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("集中するとき")
            } footer: {
                Text("「始める」「5分だけやる」を押すと、TaskFlow の通知は自動で止まり、終わると戻ります。ほかのアプリの通知も止めたいときは、この設定をオンにして、ショートカットを2つ作ってください。iPhone の決まりで、アプリから直接は集中モードを切り替えられないためです。")
            }

            Section {
                Picker(
                    "1日の区切り",
                    selection: Binding(
                        get: { viewModel.dayStartHour },
                        set: { viewModel.setDayStartHour($0) }
                    )
                ) {
                    ForEach(HomeViewModel.dayStartHourRange, id: \.self) { hour in
                        Text("\(hour)時").tag(hour)
                    }
                }
            } header: {
                Text("1日")
            } footer: {
                Text("「今日」が始まる時刻です。夜中まで作業する人は、4時などにすると、深夜の作業が前の日の分として数えられます。")
            }

            Section {
                NavigationLink {
                    TaskArchiveListView(
                        title: "保管したタスク",
                        emptyMessage: "保管したタスクはありません",
                        tasks: viewModel.archivedTasks,
                        restoreTitle: "戻す",
                        onRestore: { viewModel.restoreArchived($0) },
                        onDelete: { viewModel.deleteArchived($0) }
                    )
                } label: {
                    LabeledContent("保管したタスク", value: "\(viewModel.archivedTasks.count)件")
                }
            } header: {
                Text("片づけ")
            } footer: {
                Text("完了して\(HomeViewModel.completedHideDays)日たったものは一覧から隠れます（消えません）。\(HomeViewModel.letGoDormantDays)日以上冬眠しているものは、月に1回「手放しますか？」と聞きます。手放したものはここに保管されます。")
            }

            Section {
                ShareLink(
                    item: BackupExport(data: viewModel.makeBackup(), fileName: viewModel.backupFileName),
                    preview: SharePreview(viewModel.backupFileName)
                ) {
                    Label("データを書き出す", systemImage: "square.and.arrow.up")
                }

                Button {
                    isImporting = true
                } label: {
                    Label("書き出したデータを読み込む", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("データ")
            } footer: {
                Text("書き出したファイルは、機種変更やもしものときの控えに使えます。読み込みでは、今あるタスクは消さず、まだないものだけを足します。")
            }

            Section {
                Button("使い方をもう一度見る") {
                    viewModel.showOnboardingAgain()
                }

                LabeledContent("バージョン", value: appVersion)
            }
        }
        .navigationTitle("設定")
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            importMessage = Self.importBackup(result, into: viewModel)
        }
        .alert(
            "読み込み",
            isPresented: Binding(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } }
            )
        ) {
            Button("OK") {
                importMessage = nil
            }
        } message: {
            Text(importMessage ?? "")
        }
    }

    /// 選んだファイルを読み込んで、結果の文を返す
    private static func importBackup(
        _ result: Result<URL, Error>,
        into viewModel: HomeViewModel
    ) -> String {
        do {
            let url = try result.get()
            let isScoped = url.startAccessingSecurityScopedResource()
            defer {
                if isScoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let summary = try viewModel.importBackup(Data(contentsOf: url))
            return summary.total == 0
                ? "新しく足すものはありませんでした。"
                : "タスク\(summary.addedTasks)件、くり返し\(summary.addedRecurringTasks)件、保管\(summary.addedArchivedTasks)件を足しました。"
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? "読み込めませんでした。"
        }
    }

    private static func date(fromMinutes minutes: Int) -> Date {
        Calendar.current.date(byAdding: .minute, value: minutes, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    private static func minutes(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

/// 保管したタスクや、隠れた完了済みのタスクを見る一覧
struct TaskArchiveListView: View {

    let title: String
    let emptyMessage: String
    let tasks: [TaskItem]
    var restoreTitle: String? = nil
    var onRestore: (TaskItem) -> Void = { _ in }
    var onDelete: ((TaskItem) -> Void)? = nil

    @State private var deleting: TaskItem?

    var body: some View {
        List {
            if tasks.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tasks) { task in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                            .strikethrough(task.isCompleted)

                        Text("所要時間：\(task.estimatedMinutes)分")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .leading) {
                        if let restoreTitle {
                            Button {
                                onRestore(task)
                            } label: {
                                Label(restoreTitle, systemImage: "arrow.uturn.backward")
                            }
                            .tint(.blue)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if onDelete != nil {
                            Button(role: .destructive) {
                                deleting = task
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .alert(
            "このタスクを削除しますか？",
            isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }
            ),
            presenting: deleting
        ) { task in
            Button("削除", role: .destructive) {
                onDelete?(task)
                deleting = nil
            }

            Button("キャンセル", role: .cancel) {
                deleting = nil
            }
        } message: { task in
            Text("「\(task.title)」は元に戻せません。")
        }
    }
}

/// 長く冬眠しているタスクを、まとめて手放す画面（削除ではなく保管）
struct LetGoView: View {

    @Environment(\.dismiss) private var dismiss

    let tasks: [TaskItem]
    let onLetGo: (Set<UUID>) -> Void
    let onLater: () -> Void

    @State private var selection: Set<UUID>

    init(
        tasks: [TaskItem],
        onLetGo: @escaping (Set<UUID>) -> Void,
        onLater: @escaping () -> Void
    ) {
        self.tasks = tasks
        self.onLetGo = onLetGo
        self.onLater = onLater
        _selection = State(initialValue: Set(tasks.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(tasks) { task in
                        Button {
                            if selection.contains(task.id) {
                                selection.remove(task.id)
                            } else {
                                selection.insert(task.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selection.contains(task.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selection.contains(task.id) ? Color.accentColor : Color.secondary)

                                Text(task.title)

                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("\(HomeViewModel.letGoDormantDays)日以上、冬眠しているタスク")
                } footer: {
                    Text("手放しても消えません。設定の「保管したタスク」から、いつでも戻せます。")
                }

                Section {
                    Button("選んだ\(selection.count)件を手放す") {
                        onLetGo(selection)
                        dismiss()
                    }
                    .disabled(selection.isEmpty)

                    Button("今はこのまま") {
                        onLater()
                        dismiss()
                    }
                }
            }
            .navigationTitle("手放しますか？")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
