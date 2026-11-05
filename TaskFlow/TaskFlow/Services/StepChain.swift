import Foundation

/// 「一歩」のつながりを扱う（UIや保存に触れない純粋なロジック）
///
/// 一歩は元のタスクにぶら下がり（`parentTaskID`）、まだ済んでいない一歩が決めた順に前提としてつながる。
/// 元のタスクは最後の一歩を待つ。
enum StepChain {

    /// 元のタスクの一歩（並び順。済んだものも含む）
    static func steps(of parentID: UUID, in tasks: [TaskItem]) -> [TaskItem] {
        tasks.filter { $0.parentTaskID == parentID }
    }

    /// 一歩を、決めた順につなぎ直す
    ///
    /// 元のタスクがもともと待っていた前提（一歩以外）は、最初の一歩が待つ。
    static func rebuild(parentID: UUID, in tasks: inout [TaskItem]) {
        guard let parentIndex = tasks.firstIndex(where: { $0.id == parentID }) else {
            return
        }

        let stepIndices = tasks.indices.filter { tasks[$0].parentTaskID == parentID }
        let stepIDs = Set(stepIndices.map { tasks[$0].id })

        var external: [UUID] = []
        for id in tasks[parentIndex].prerequisiteIDs + stepIndices.flatMap({ tasks[$0].prerequisiteIDs })
        where !stepIDs.contains(id) && id != parentID && !external.contains(id) {
            external.append(id)
        }

        var previous: UUID?
        for index in stepIndices where !tasks[index].isCompleted {
            tasks[index].prerequisiteIDs = previous.map { [$0] } ?? external
            previous = tasks[index].id
        }

        tasks[parentIndex].prerequisiteIDs = external + (previous.map { [$0] } ?? [])
    }

    /// まだ済んでいない一歩の順番を入れ替える（List の onMove と同じ意味）
    static func moveOpenSteps(
        of parentID: UUID,
        fromOffsets source: IndexSet,
        toOffset destination: Int,
        in tasks: inout [TaskItem]
    ) {
        let original = steps(of: parentID, in: tasks).filter { !$0.isCompleted }

        let moving = source.sorted().map { original[$0] }
        var open = original.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        open.insert(contentsOf: moving, at: min(max(insertAt, 0), open.count))

        let openIDs = Set(open.map(\.id))
        tasks.removeAll { openIDs.contains($0.id) }

        guard let parentIndex = tasks.firstIndex(where: { $0.id == parentID }) else {
            return
        }

        tasks.insert(contentsOf: open, at: parentIndex)
        rebuild(parentID: parentID, in: &tasks)
    }

    /// 以前の形（「元のタスク名：一歩」というタイトル）の一歩を、元のタスクにぶら下がる形に直す
    ///
    /// 以前は一歩の一歩も作れたので「元：一歩目：二歩目」のように重なっていることがある。
    /// 元のタスク名を外したあと、同じ元のタスクのほかの一歩の名前が頭に付いていれば、それも外す。
    ///
    /// - Returns: 何か直したか
    static func migrateLegacySteps(in tasks: inout [TaskItem]) -> Bool {
        var changed = false
        var touchedParents: Set<UUID> = []

        for index in tasks.indices where tasks[index].parentTaskID == nil {
            guard let groupID = tasks[index].splitGroupID,
                  groupID != tasks[index].id,
                  let parent = tasks.first(where: { $0.id == groupID }) else {
                continue
            }

            let prefix = CompletionMessages.baseTitle(of: parent.title) + "："
            guard tasks[index].title.hasPrefix(prefix) else {
                continue
            }

            tasks[index].title = String(tasks[index].title.dropFirst(prefix.count))
            tasks[index].parentTaskID = parent.id
            touchedParents.insert(parent.id)
            changed = true
        }

        // 一歩の名前の頭に、ほかの一歩の名前が重なっていたら外す（長い名前から順に試す）
        for index in tasks.indices {
            guard let parentID = tasks[index].parentTaskID else {
                continue
            }

            let siblingTitles = tasks
                .filter { $0.parentTaskID == parentID && $0.id != tasks[index].id }
                .map(\.title)
                .sorted { $0.count > $1.count }

            var stripped = true
            while stripped {
                stripped = false
                for sibling in siblingTitles where !sibling.isEmpty {
                    let prefix = sibling + "："
                    if tasks[index].title.hasPrefix(prefix), tasks[index].title.count > prefix.count {
                        tasks[index].title = String(tasks[index].title.dropFirst(prefix.count))
                        touchedParents.insert(parentID)
                        changed = true
                        stripped = true
                        break
                    }
                }
            }
        }

        for parentID in touchedParents {
            rebuild(parentID: parentID, in: &tasks)
        }

        return changed
    }
}
