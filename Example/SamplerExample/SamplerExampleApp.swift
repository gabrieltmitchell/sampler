import SwiftUI
import Sampler

@main
struct SamplerExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    #if DEBUG
                    DispatchQueue.main.async {
                        Sampler.start()
                    }
                    #endif
                }
        }
    }
}
