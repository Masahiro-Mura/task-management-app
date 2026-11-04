import SwiftUI

struct ContentView: View {

    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var viewModel = HomeViewModel()
    @State private var isShowingAddTask = false

    /// 推薦を計算し直す間隔。期限までの残り時間などを時間経過に合わせて更新する
    private let refreshInterval: Duration = .seconds(60)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("今やること")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("登録タスク：\(viewModel.tasks.count)件")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if viewModel.tasks.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "checklist")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)

                            Text("まだタスクがありません")
                                .font(.headline)

                            Text("右上の＋ボタンから追加しましょう。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        availableMinutesPicker
                    }


                    if let recommendation = viewModel.recommendation {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")

                                Text("おすすめ")
                                    .fontWeight(.semibold)
                            }
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                            
                            Text(recommendation.task.title)
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("所要時間：\(recommendation.task.estimatedMinutes)分")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("このタスクをおすすめする理由")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(recommendation.reason)
                                    .font(.body)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.blue.opacity(0.4), lineWidth: 1)
                        }
                    } else if !viewModel.tasks.isEmpty,
                              let summary = viewModel.noRecommendationSummary {
                        noRecommendationCard(summary)
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "sun.max")

                            Text("今日")
                        }
                        .font(.title2)
                        .fontWeight(.bold)
                        
                        if viewModel.todayTasks.isEmpty {
                            Text("今日のタスクはありません")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.todayTasks) { task in
                                TaskRowView(
                                    task: task,
                                    note: viewModel.isCarriedOver(task) ? "持ち越し" : nil,
                                    onToggleCompletion: {
                                        viewModel.toggleCompletion(for: task)
                                    }
                                )
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")

                            Text("明日")
                        }
                        .font(.title2)
                        .fontWeight(.bold)
                        
                        if viewModel.tomorrowTasks.isEmpty {
                            Text("明日のタスクはありません")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.tomorrowTasks) { task in
                                TaskRowView(
                                    task: task,
                                    onToggleCompletion: {
                                        viewModel.toggleCompletion(for: task)
                                    }
                                )
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    
                    NavigationLink {
                        AllTasksView(
                            tasks: viewModel.allTasks,
                            dormantTaskIDs: viewModel.dormantTaskIDs,
                            onToggleCompletion: { task in
                                viewModel.toggleCompletion(for: task)
                            },
                            onDelete: { task in
                                viewModel.deleteTask(task)
                            },
                            onUpdate: { updatedTask in
                                viewModel.updateTask(updatedTask)
                            },
                            onWake: { task in
                                viewModel.wakeTask(task)
                            }
                        )
                    } label: {
                        HStack(spacing: 8){
                            Image(systemName: "list.bullet")
                            Text("すべてのタスク")
                                .font(.title2)
                                .fontWeight(.bold)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("TaskFlow")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingAddTask = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("タスクを追加")
                }
            }
            .sheet(isPresented: $isShowingAddTask) {
                AddTaskView { title, estimatedMinutes, priority, scheduledDate, deadline in
                    viewModel.addTask(
                        title: title,
                        estimatedMinutes: estimatedMinutes,
                        priority: priority,
                        scheduledDate: scheduledDate,
                        deadline: deadline
                    )
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    viewModel.updateRecommendation()
                }
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: refreshInterval)
                    viewModel.updateRecommendation()
                }
            }
        }
    }

    /// 今使える時間の選択
    private var availableMinutesPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("今使える時間")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker(
                "今使える時間",
                selection: Binding(
                    get: { viewModel.availableMinutes },
                    set: { viewModel.setAvailableMinutes($0) }
                )
            ) {
                ForEach(HomeViewModel.availableMinuteOptions, id: \.self) { minutes in
                    Text("\(minutes)分")
                        .tag(minutes)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    /// 推薦できるタスクがないときに、その内訳と次の一手を示す
    private func noRecommendationCard(
        _ summary: NoRecommendationSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if summary.allCompleted {
                Label("すべてのタスクが完了しています", systemImage: "checkmark.circle")
                    .font(.headline)
            } else {
                Label("今の空き時間で取りかかれるタスクはありません", systemImage: "clock")
                    .font(.headline)

                if summary.tooLongCount > 0,
                   let shortest = summary.shortestTooLongMinutes {
                    Text("空き時間\(viewModel.availableMinutes)分に収まらないタスクが\(summary.tooLongCount)件あります（最短\(shortest)分）")
                }

                if summary.waitingForPrerequisitesCount > 0 {
                    Text("前提タスクの完了を待っているタスクが\(summary.waitingForPrerequisitesCount)件あります")
                }

                if summary.dormantCount > 0 {
                    Text("冬眠中のタスクが\(summary.dormantCount)件あります（「すべてのタスク」から起こせます）")
                }

                if let suggested = viewModel.suggestedAvailableMinutes {
                    Button("空き時間を\(suggested)分にする") {
                        viewModel.setAvailableMinutes(suggested)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
            }
        }
        .font(.subheadline)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    ContentView()
}
