//
//  TaskFlowApp.swift
//  TaskFlow
//
//  Created by Masahiro Mura on 2026/07/12.
//

import SwiftUI
import UIKit

@main
struct TaskFlowApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// 画面の向きを決める
///
/// iPhone では縦向きに固定する（「開いて1つ分かる」画面は縦で読む前提のため）。iPad は回転できる。
/// 向きの設定はプロジェクトファイルにもあるが、`project.pbxproj` は手で編集しない方針なので、ここで決める。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait
    }
}
