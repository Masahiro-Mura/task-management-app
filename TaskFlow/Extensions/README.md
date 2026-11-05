# ウィジェットと共有シート（ターゲットを足す前の置き場）

ここのコードは、まだどのターゲットにも入っていない（`project.pbxproj` を手で編集しない方針のため、ターゲットは Xcode で足す）。
下の手順が済んだら、Claude Code がこのフォルダの中身を新しいターゲットのフォルダに移し、テンプレートのファイルと置き換えてビルドする。

- `TaskFlowWidget/` … ホーム画面・ロック画面の「今の1つ」（`TodayPickWidget`）と、集中中のライブアクティビティ（`FocusLiveActivityWidget`）
- `TaskFlowShare/` … 共有シートから足す（`ShareViewController`）
- アプリと分け合う型は `TaskFlow/Shared/`（`SharedStore`, `WidgetSnapshot`, `ShareInbox`, `WidgetLink`, `FocusActivityAttributes`）

## Xcode でやること

1. **ウィジェットのターゲットを足す。** File → New → Target… → iOS の「Widget Extension」
   - Product Name：`TaskFlowWidget`
   - 「Include Live Activity」「Include Control」「Include Configuration App Intent」は**すべて外す**（コードはこちらで用意してある）
   - 「Activate “TaskFlowWidget” scheme?」は Cancel でよい
2. **共有シートのターゲットを足す。** File → New → Target… → iOS の「Share Extension」
   - Product Name：`TaskFlowShare`
   - scheme の確認は Cancel でよい
3. **App Group を3つのターゲットに付ける。** TaskFlow・TaskFlowWidget・TaskFlowShare のそれぞれで、Signing & Capabilities → 「+ Capability」→「App Groups」→「+」で `group.com.masahiromura.TaskFlow`（3つとも同じ名前。チームの選択が要る）
4. **ライブアクティビティを許す。** TaskFlow ターゲットの Info タブで「+」→ キー `NSSupportsLiveActivities`（Supports Live Activities）を YES
5. **分け合うフォルダを拡張にも入れる。** 左のナビゲータで `TaskFlow/Shared` フォルダを選び、右の File インスペクタの Target Membership で TaskFlowWidget と TaskFlowShare にもチェック

終わったら「ターゲットを足した」と伝える。

## 動き

- アプリが推薦を出し直すたびに、「今の1つ」の写しを App Group に書いてウィジェットを描き直す（中身が変わったときだけ）
- ウィジェット（中サイズ）の「始める」「5分だけ」、ロック画面の丸いウィジェットは、アプリを開いてそのまま集中を始める（`taskflow://focus?...`）
- 集中しているあいだは、ロック画面とダイナミックアイランドに経過時間を出す（残り時間で急かさない）
- 共有シートは受け箱に入れるだけ。次にアプリを開いたとき、1行入力と同じ読み方（名前を整える・日付や時間を読む）でタスクにする。ページを共有したときは「〇〇」を読む、にしてURLも残す（カードの「…」→「リンクを開く」）
- App Group を付ける前でも、アプリはこれまでどおり動く（写しも受け箱も使わないだけ）
