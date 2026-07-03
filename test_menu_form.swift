import SwiftUI
import AppKit

struct TestView: View {
    @State var sel = 1
    var body: some View {
        Form {
            Section("Settings") {
                Picker("Picker", selection: $sel) {
                    Text("One").tag(1)
                    Text("Two").tag(2)
                }
                
                Menu {
                    Button("One") { sel = 1 }
                    Button("Two") { sel = 2 }
                } label: {
                    Text(sel == 1 ? "One" : "Two")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 400, height: 300)
    }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let w = NSWindow(contentRect: NSRect(x:0,y:0,width:400,height:300), styleMask: [.titled], backing: .buffered, defer: false)
        w.contentView = NSHostingView(rootView: TestView())
        w.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
    }
}
app.run()
