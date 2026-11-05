import SwiftUI

/// くり返しの選択。種類は 毎日／毎週◯曜／毎月◯日／◯日ごと の4つに絞る
struct RecurrenceSection: View {

    /// nil なら、くり返さない
    @Binding var recurrence: Recurrence?

    /// 「くり返さない」を選べるか（くり返しの編集画面では選べない）
    var allowsNone = true

    private enum Kind: Hashable {
        case none, daily, weekly, monthly, everyNDays

        var title: String {
            switch self {
            case .none: return String(localized: "なし")
            case .daily: return String(localized: "毎日")
            case .weekly: return String(localized: "毎週")
            case .monthly: return String(localized: "毎月")
            case .everyNDays: return String(localized: "◯日ごと")
            }
        }
    }

    private var kind: Kind {
        switch recurrence?.rule {
        case nil: return .none
        case .daily: return .daily
        case .weekly: return .weekly
        case .monthly: return .monthly
        case .everyNDays: return .everyNDays
        }
    }

    private var kinds: [Kind] {
        allowsNone ? [.none, .daily, .weekly, .monthly, .everyNDays] : [.daily, .weekly, .monthly, .everyNDays]
    }

    var body: some View {
        Section {
            Picker(
                "くり返し",
                selection: Binding(
                    get: { kind },
                    set: { setKind($0) }
                )
            ) {
                ForEach(kinds, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }

            if let recurrence {
                ruleDetail(for: recurrence.rule)

                Toggle(
                    "祝日はお休み",
                    isOn: Binding(
                        get: { recurrence.skipsHolidays },
                        set: { self.recurrence?.skipsHolidays = $0 }
                    )
                )

                Toggle(
                    "やり残しを次の日に持ち越す",
                    isOn: Binding(
                        get: { recurrence.carriesOver },
                        set: { self.recurrence?.carriesOver = $0 }
                    )
                )
            }
        } header: {
            Text("くり返し")
        } footer: {
            if recurrence != nil {
                Text("前の回が終わっていなくても、次の回は予定どおり出ます。持ち越さない場合、過ぎた回は静かに消えます。")
            }
        }
    }

    @ViewBuilder
    private func ruleDetail(for rule: Recurrence.Rule) -> some View {
        switch rule {
        case .daily:
            EmptyView()

        case .weekly(let weekdays):
            weekdayPicker(selected: Set(weekdays))

        case .monthly(let day):
            Stepper(
                "毎月\(day)日",
                value: Binding(
                    get: { day },
                    set: { recurrence?.rule = .monthly(day: $0) }
                ),
                in: 1...31
            )

        case .everyNDays(let n):
            Stepper(
                "\(n)日ごと",
                value: Binding(
                    get: { n },
                    set: { recurrence?.rule = .everyNDays($0) }
                ),
                in: 2...30
            )
        }
    }

    /// 月曜はじまりの曜日ボタン
    private func weekdayPicker(selected: Set<Int>) -> some View {
        HStack(spacing: 6) {
            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { weekday in
                let isOn = selected.contains(weekday)

                Button {
                    var next = selected
                    if isOn {
                        // 最後の1つは外せない（曜日なしの毎週にならないように）
                        guard next.count > 1 else { return }
                        next.remove(weekday)
                    } else {
                        next.insert(weekday)
                    }
                    recurrence?.rule = .weekly(weekdays: next.sorted())
                } label: {
                    Text(Recurrence.weekdaySymbols[weekday - 1])
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .background(isOn ? Color.accentColor : Color.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Recurrence.weekdayNames[weekday - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    private func setKind(_ newKind: Kind) {
        let today = Calendar.current.component(.weekday, from: Date())
        let dayOfMonth = Calendar.current.component(.day, from: Date())
        let skipsHolidays = recurrence?.skipsHolidays ?? false
        let carriesOver = recurrence?.carriesOver ?? false

        let rule: Recurrence.Rule?
        switch newKind {
        case .none: rule = nil
        case .daily: rule = .daily
        case .weekly: rule = .weekly(weekdays: [today])
        case .monthly: rule = .monthly(day: dayOfMonth)
        case .everyNDays: rule = .everyNDays(2)
        }

        recurrence = rule.map { Recurrence(rule: $0, skipsHolidays: skipsHolidays, carriesOver: carriesOver) }
    }
}
