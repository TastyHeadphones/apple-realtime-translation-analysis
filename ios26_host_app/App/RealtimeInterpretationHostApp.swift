import SwiftUI
import RealtimeInterpretationDemo

@main
struct RealtimeInterpretationHostApp: App {
    var body: some Scene {
        WindowGroup {
            if #available(iOS 26.4, *) {
                RealtimeInterpreterView()
            } else {
                ContentUnavailableView(
                    "Requires iOS 26.4+",
                    systemImage: "iphone.gen3.slash",
                    description: Text("This demo depends on iOS 26.4 Translation and Speech APIs.")
                )
            }
        }
    }
}

