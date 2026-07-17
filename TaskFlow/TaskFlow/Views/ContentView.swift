import SwiftUI

struct ContentView: View {

    @StateObject private var viewModel = HomeViewModel()
    @State private var isShowingAddTask = false

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
                    }

                    
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
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("今日")
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
                                    onToggleCompletion: {
                                        viewModel.toggleCompletion(for: task)
                                    }
                                )
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("明日")
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
                    VStack(alignment: .leading, spacing: 12) {
                        Text("すべて")
                            .font(.title2)
                            .fontWeight(.bold)

                        if viewModel.allTasks.isEmpty {
                            Text("タスクはありません")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.allTasks) { task in
                                TaskRowView(
                                    task: task,
                                    onToggleCompletion: {
                                        viewModel.toggleCompletion(for: task)
                                    },
                                    onDelete: {
                                        viewModel.deleteTask(task)
                                    }
                                )
                            }
                        }
                    }
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
                AddTaskView { title, estimatedMinutes, scheduledDate, deadline in
                    viewModel.addTask(
                        title: title,
                        estimatedMinutes: estimatedMinutes,
                        scheduledDate: scheduledDate,
                        deadline: deadline
                    )
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
