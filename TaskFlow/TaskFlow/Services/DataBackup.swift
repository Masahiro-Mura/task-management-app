import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// 書き出し・読み込みに使う、全データのまとまり
struct BackupFile: Codable, Equatable {
    /// 形式の版。形が変わったら上げる
    static let currentVersion = 1

    var version: Int
    var exportedAt: Date
    var tasks: [TaskItem]
    var recurringTasks: [RecurringTask]
    var archivedTasks: [TaskItem]

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// 読み込んだ結果
struct BackupImportSummary: Equatable {
    var addedTasks: Int
    var addedRecurringTasks: Int
    var addedArchivedTasks: Int

    var total: Int {
        addedTasks + addedRecurringTasks + addedArchivedTasks
    }
}

enum BackupError: LocalizedError {
    case unreadable
    case newerVersion

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "TaskFlow の書き出しファイルとして読めませんでした。"
        case .newerVersion:
            return "新しい版の TaskFlow で書き出したファイルです。アプリを更新してから読み込んでください。"
        }
    }
}

/// 共有シートで渡す書き出しファイル
struct BackupExport: Transferable {
    let data: Data
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { export in
            export.data
        }
        .suggestedFileName { $0.fileName }
    }
}
