import AppKit

@main
enum LinkDeckMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        let selfTesting = CommandLine.arguments.contains("--self-test")
        application.setActivationPolicy(selfTesting ? .prohibited : .regular)
        application.run()
    }
}
