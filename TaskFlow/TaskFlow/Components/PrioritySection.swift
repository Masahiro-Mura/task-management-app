import SwiftUI

/// 優先度の選択。「高」は同時に3件まで。4件目を高にしようとしたら、どれを中に戻すか聞く
///
/// 全部が「高」になって、結局どれから手を付けるか分からなくなるのを防ぐため。
struct PrioritySection: View {

    @Binding var priority: TaskPriority

    /// 保存するときに「中」に戻すタスク
    @Binding var lowering: UUID?

    /// このタスク以外で、優先度「高」の未完了タスク
    let otherHighPriorityTasks: [TaskItem]

    @State private var isAskingWhichToLower = false

    private var loweringTitle: String? {
        otherHighPriorityTasks.first { $0.id == lowering }?.title
    }

    var body: some View {
        Section {
            Picker(
                "優先度",
                selection: Binding(
                    get: { priority },
                    set: { newValue in
                        if newValue == .high,
                           priority != .high,
                           otherHighPriorityTasks.count >= HomeViewModel.maxHighPriorityTasks {
                            isAskingWhichToLower = true
                            return
                        }

                        if newValue != .high {
                            lowering = nil
                        }
                        priority = newValue
                    }
                )
            ) {
                ForEach(TaskPriority.allCases, id: \.self) { priority in
                    Text(priority.displayName)
                        .tag(priority)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("優先度")
        } footer: {
            if let loweringTitle {
                Text("保存すると「\(loweringTitle)」を「中」に戻します。")
            } else {
                Text("迷ったら「中」のままで大丈夫です。期限と時間から推薦が決めます。")
            }
        }
        .confirmationDialog(
            "「高」は\(HomeViewModel.maxHighPriorityTasks)件までです",
            isPresented: $isAskingWhichToLower,
            titleVisibility: .visible
        ) {
            ForEach(otherHighPriorityTasks) { task in
                Button("「\(task.title)」を中にする") {
                    lowering = task.id
                    priority = .high
                }
            }

            Button("やめる", role: .cancel) {}
        } message: {
            Text("どれかを「中」に戻すと、このタスクを「高」にできます。")
        }
    }
}
