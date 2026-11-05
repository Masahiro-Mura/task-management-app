# TaskFlow

「次に何をやるか」を1件だけ提案する、個人開発のiOSタスク管理アプリ。一覧を眺めさせるのではなく、今の空き時間・期限・前提タスクから"今やること"を決めて理由つきで示すのが核。

## 技術スタック

- SwiftUI / iOS(Deployment Target 26.5)、Swift 5 モード、`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- 永続化は `UserDefaults`(JSON)。外部依存・SwiftPMパッケージなし
- テストは **Swift Testing**(`import Testing` / `@Test` / `#expect`)。XCTestではない(UITestsのみXCTest)
- UI文言・コメントは日本語

## 構成

```
TaskFlow/
  App/          TaskFlowApp.swift（エントリポイント）
  Models/       TaskItem, TaskPriority, DecisionContext
  Services/     DecisionEngine（推薦ロジック）, PrerequisiteRules（前提に選べるタスク）, TaskSplitter（分解）, QuickAddParser（1行追加の読み取り）, CompletionMessages（完了のひとこと）。いずれもUIに依存しない純粋なロジック
  ViewModels/   HomeViewModel（タスク一覧・保存・推薦の更新）
  Views/        ContentView(ホーム), AddTaskView, EditTaskView, AllTasksView, SplitTaskView, FocusView（集中画面）, DoneTodayView（今日やったこと）, CarryOverView（持ち越しの整理）
  Components/   TaskRowView, CelebrationView（完了のお祝い）, PrioritySection（「高」は3件まで）
TaskFlowTests/      ロジックの単体テスト
TaskFlowUITests/    UIテスト
```

- `.xcodeproj` はファイルシステム同期グループ(objectVersion 77)。`TaskFlow/` 配下に新しい `.swift` を作れば自動でターゲットに入る。**`project.pbxproj` を手で編集しない。**
- `xcuserdata/` と `.DS_Store` はコミットしない。

## ビルドとテスト

```bash
# 利用可能なシミュレータを確認して名前を決める
xcrun simctl list devices available

xcodebuild -project TaskFlow.xcodeproj -scheme TaskFlow \
  -destination 'platform=iOS Simulator,name=<上で確認した名前>' build

xcodebuild -project TaskFlow.xcodeproj -scheme TaskFlow \
  -destination 'platform=iOS Simulator,name=<上で確認した名前>' test \
  -only-testing:TaskFlowTests
```

UIの見た目の確認はXcodeのPreview/シミュレータで人が行う。ロジックの変更はまず `TaskFlowTests` にテストを足して確かめる。

## 設計方針

- 推薦ロジック(`DecisionEngine`)はViewやUserDefaultsに触れない。入力は `[TaskItem]` と `DecisionContext`、出力は `TaskRecommendation?`。現在時刻は `DecisionContext.currentDate` で注入し、テストで固定できるようにする。
- 推薦には必ず理由文(`reason`)を付ける。理由を出せない判断は入れない。
- 状態の変更は `HomeViewModel` を経由し、変更のたびに `saveTasks()` → `updateRecommendation()` を呼ぶ。
- `TaskItem` の `Codable` は後方互換を保つ。フィールドを足すときは `init(from:)` で `decodeIfPresent` を使い、既存の保存データを壊さない。
- 機能は足しすぎない。シンプルさ（開いて、今やる1つが分かる）を優先する。

## 製品の方向性（市場調査より）

差別化の軸は「現実的な1日」「罪悪感を生まない」こと。

- 空き時間に入らないものを隠さず、正直に示す
- 期限切れや溜まったタスクで責めない（放置タスクは冬眠させる等）
- 着手しやすさ（大きいタスクを小さく分解、"今やる1つ"）
- MCP/AIエージェント連携は当面やらない（後回し）。端末内のAIで分解の候補を出すのは可（非対応機種でも動くこと）
- 連続日数・ポイント・赤いバッジなど、途切れたときに罪悪感を生む仕組みは入れない

## 既知の課題と改修計画

既知の不具合・課題と、フェーズごとの改修計画は [ROADMAP.md](ROADMAP.md) にまとめてある。作業を始める前に読み、終えたらチェックを更新する。上から順（フェーズ0から）に進める。
