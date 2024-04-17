//
//  NiiVueApp.swift
//  NiiVue
//
//  Created by Taylor Hanayik on 03/01/2024.
//

import SwiftUI

@main
struct NiiVueApp: App {
    @StateObject var sharedData = SharedData()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sharedData)
        }
//        .commands {
//                    CommandMenu("Custom") {
//                        Button("Item 1") {}
//                        Divider()
//                        Button("Item 2") {}
//                    }
//                    CommandMenu("Another one") {
//                        Button("Item 3") {}
//                        Divider()
//                        Button("Item 4") {}
//                    }
//                }
    }
}
