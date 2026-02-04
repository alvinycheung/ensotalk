import SwiftUI
import AVFoundation
import Carbon.HIToolbox

@main
struct EnsoTalkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var chatManager: ChatManager?
    var hotKeyRef: EventHotKeyRef?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
        
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "EnsoTalk")
            button.action = #selector(togglePopover)
        }
        
        // Create popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 320, height: 200)
        popover?.behavior = .transient
        
        chatManager = ChatManager()
        popover?.contentViewController = NSHostingController(rootView: ChatView(manager: chatManager!))
        
        // Register global hotkey (Option+Space)
        registerHotKey()
    }
    
    func registerHotKey() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x4550_5354) // "EPST"
        hotKeyID.id = 1
        
        // Option + Space (keycode 49 = space)
        let modifiers: UInt32 = UInt32(optionKey)
        RegisterEventHotKey(49, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        
        // Install handler
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
            appDelegate.handleHotKey()
            return noErr
        }, 1, &eventSpec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }
    
    func handleHotKey() {
        Task { @MainActor in
            chatManager?.toggleRecording()
        }
    }
    
    @objc func togglePopover() {
        if let button = statusItem?.button {
            if popover?.isShown == true {
                popover?.performClose(nil)
            } else {
                popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
