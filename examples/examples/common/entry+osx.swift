// Copyright 2016 Stuart Carnie.
// License: https://github.com/stuartcarnie/SwiftBGFX#license-bsd-2-clause
//

import Foundation
import AppKit
import SwiftBGFX

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var applicationHasTerminated = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("did finish launching")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        self.applicationHasTerminated = true
    }
}

class WindowDelegate: NSObject, NSWindowDelegate {
    func windowCreated(_ window: NSWindow) {
        window.delegate = self
    }
    
    func windowShouldClose(_ sender: Any) -> Bool {
        let win = sender as! NSWindow
        
        win.delegate = nil
        NSApp.terminate(self)
        return false
    }
    
    func windowDidResize(_ notification: Notification) {
        s_ctx.windowDidResize()
    }
}

class MainThreadEntry {
    
    func execute() {
        runApp(sharedApp, argc: 0, argv: [])
    }
}

func ch(_ c: UnicodeScalar) -> Int {
    return Int(c.value)
}

class Context {
    private var eventQueue: EventQueue = EventQueue()
    
    var translateKey = [KeyCode](repeating: .none, count: 256)
    
    init() {
        translateKey[27] = .esc
        translateKey[ch("\n")] = .return
        translateKey[ch("\t")] = .tab
        translateKey[127] = .backspace
        translateKey[ch(" ")] = .space
        
        translateKey[ch("+")] = .plus
        translateKey[ch("=")] = .plus
        translateKey[ch("_")] = .minus
        translateKey[ch("-")] = .minus
        
        translateKey[ch("~")] = .tilde
        translateKey[ch("`")] = .tilde
        
        translateKey[ch(":")] = .semicolon
        translateKey[ch(";")] = .semicolon
        translateKey[ch("\"")] = .quote
        translateKey[ch("'")] = .quote
        
        translateKey[ch("{")] = .leftBracket
        translateKey[ch("[")] = .leftBracket
        translateKey[ch("}")] = .rightBracket
        translateKey[ch("]")] = .rightBracket
        
        translateKey[ch("<")] = .comma
        translateKey[ch(",")] = .comma
        translateKey[ch(">")] = .period
        translateKey[ch(".")] = .period
        translateKey[ch("?")] = .slash
        translateKey[ch("/")] = .slash
        translateKey[ch("|")] = .backslash
        translateKey[ch("\\")] = .backslash
        
        translateKey[ch("0")] = .key0
        translateKey[ch("1")] = .key1
        translateKey[ch("2")] = .key2
        translateKey[ch("3")] = .key3
        translateKey[ch("4")] = .key4
        translateKey[ch("5")] = .key5
        translateKey[ch("6")] = .key6
        translateKey[ch("7")] = .key7
        translateKey[ch("8")] = .key8
        translateKey[ch("9")] = .key9
        
        let a = ch("a")
        let spc = ch(" ")
        for char in a...ch("z") {
            let v = char - a
            let k = KeyCode(rawValue: KeyCode.keyA.rawValue + v)!
            translateKey[char] = k
            translateKey[char - spc] = k
        }
    }
    
    // mouse
    var mx: UInt16 = 0
    var my: UInt16 = 0
    var scroll: Int32 = 0
    var scrollf: CGFloat = 0.0
    
    var win: NSWindow!
    var winDelegate: WindowDelegate = WindowDelegate()
    
    func run() {
        NSApplication.shared()
        
        let dg = AppDelegate()
        NSApp.delegate = dg
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.finishLaunching()
        
        NotificationCenter.default
            .post(name: NSNotification.Name.NSApplicationWillFinishLaunching, object: NSApp)
        NotificationCenter.default
            .post(name: NSNotification.Name.NSApplicationDidFinishLaunching, object: NSApp)
        
        let qmi = NSMenuItem(title: "Quit", action: #selector(NSApp.terminate), keyEquivalent: "q")
        
        let menu = NSMenu(title: "Example")
        menu.addItem(qmi)
        
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = menu
        
        let menuBar = NSMenu()
        menuBar.addItem(appMenuItem)
        NSApp.mainMenu = menuBar
        
        let rect = NSRect(x: 100, y: 100, width: 1280, height: 720)
        let style: NSWindowStyleMask = [.titled , .closable , .resizable , .miniaturizable]
        
        let win = NSWindow(contentRect: rect, styleMask: style, backing: .buffered, defer: false)
        win.title = ProcessInfo.processInfo.processName
        win.makeKeyAndOrderFront(nil)
        win.acceptsMouseMovedEvents = true
        win.backgroundColor = NSColor.black
        self.win = win
        winDelegate.windowCreated(win)
        
        var pd = PlatformData()
        pd.nwh = UnsafeMutableRawPointer(Unmanaged.passRetained(win).toOpaque())
        bgfx.setPlatformData(pd)
        
        DispatchQueue.global(qos: .userInteractive).async {
            let mte = MainThreadEntry()
            mte.execute()
        }
        
        eventQueue.postSizeEvent(1280, height: 720)
        
        while !dg.applicationHasTerminated {
            if bgfx.renderFrame() == .exiting {
                break
            }
            
            while dispatchEvent(peekEvent()) {}
        }
        
        eventQueue.postExitEvent()
        
        while bgfx.renderFrame() != .nocontext {}
    }
    
    func poll() -> Event? {
        return eventQueue.poll()
    }
    
    func peekEvent() -> NSEvent? {
        return NSApp.nextEvent(matching: .any,
                               until: Date.distantPast,
                               inMode: RunLoopMode.defaultRunLoopMode,
                               dequeue: true)
    }
    
    func updateMousePos()
    {
        let originalFrame = win.frame
        let location = win.mouseLocationOutsideOfEventStream
        let adjustFrame = win.contentRect(forFrameRect: originalFrame)
        
        var x = location.x
        var y = adjustFrame.size.height - location.y
        
        // clamp within the range of the window
        if x < 0 {
            x = 0
        } else if x > adjustFrame.size.width {
            x = adjustFrame.size.width
        }
        
        if y < 0 {
            y = 0
        } else if y > adjustFrame.size.height {
            y = adjustFrame.size.height
        }
        
        mx = UInt16(x)
        my = UInt16(y)
    }
    
    func dispatchEvent(_ event: NSEvent?) -> Bool {
        guard let ev = event else {
            return false
        }
        
        switch ev.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            updateMousePos()
            eventQueue.postMouseEvent(mx, y: my, z: scroll)
            
        case .leftMouseDown:
            eventQueue.postMouseEvent(mx, y: my, z: scroll, button: .left, state: .down)
            
        case .leftMouseUp:
            eventQueue.postMouseEvent(mx, y: my, z: scroll, button: .left, state: .up)
            
        case .rightMouseDown:
            eventQueue.postMouseEvent(mx, y: my, z: scroll, button: .right, state: .down)
            
        case .rightMouseUp:
            eventQueue.postMouseEvent(mx, y: my, z: scroll, button: .right, state: .up)
            
        case .otherMouseDown:
            eventQueue.postMouseEvent(mx, y: my, z: scroll, button: .middle, state: .down)
            
        case .otherMouseUp:
            eventQueue.postMouseEvent(mx, y: my, z: scroll, button: .middle, state: .up)
            
        case .scrollWheel:
            scrollf += ev.deltaY
            scroll = Int32(scrollf)
            eventQueue.postMouseEvent(mx, y: my, z: scroll)
            
        case .keyDown:
            let (key, modifiers, _) = handleKeyEvent(ev)
            if key == .none {
                break
            }
            
            switch key {
            case .keyQ where modifiers.contains(.rightMeta):
                eventQueue.postExitEvent()
                
            default:
                eventQueue.postKeyEvent(key, modifier: modifiers, state: .down)
                return false
            }
            
        case .keyUp:
            let (key, modifiers, _) = handleKeyEvent(ev)
            if key == .none {
                break
            }
            
            eventQueue.postKeyEvent(key, modifier: modifiers, state: .up)
            return false
            
        default:
            break;
        }
        
        NSApp.sendEvent(ev)
        NSApp.updateWindows()
        
        return true
    }
    
    func handleKeyEvent(_ ev: NSEvent) -> (KeyCode, KeyModifier, UnicodeScalar) {
        guard let key = ev.charactersIgnoringModifiers else {
            return (.none, .none, "\u{0}")
        }
        
        let keyNum = key.unicodeScalars.first!
        let mod = translateModifiers(ev.modifierFlags)
        
        var keyCode: KeyCode
        if ch(keyNum) < 256 {
            keyCode = translateKey[ch(keyNum)]
        } else {
            
            switch Int(ev.keyCode) {
                
            case NSF1FunctionKey: keyCode = .f1
            case NSF2FunctionKey: keyCode = .f2
            case NSF3FunctionKey: keyCode = .f3
            case NSF4FunctionKey: keyCode = .f4
            case NSF5FunctionKey: keyCode = .f5
            case NSF6FunctionKey: keyCode = .f6
            case NSF7FunctionKey: keyCode = .f7
            case NSF8FunctionKey: keyCode = .f8
            case NSF9FunctionKey: keyCode = .f9
            case NSF10FunctionKey: keyCode = .f10
            case NSF11FunctionKey: keyCode = .f11
            case NSF12FunctionKey: keyCode = .f12
                
            case NSLeftArrowFunctionKey: keyCode = .left
            case NSRightArrowFunctionKey: keyCode = .right
            case NSUpArrowFunctionKey: keyCode = .up
            case NSDownArrowFunctionKey: keyCode = .down
                
            case NSPageUpFunctionKey: keyCode = .pageUp
            case NSPageDownFunctionKey: keyCode = .pageDown
            case NSHomeFunctionKey: keyCode = .home
            case NSEndFunctionKey: keyCode = .end
                
            case NSPrintScreenFunctionKey: keyCode = .print
                
            default:
                keyCode = .none
            }
        }
        
        return (keyCode, mod, keyNum)
    }
    
    func translateModifiers(_ flags: NSEventModifierFlags) -> KeyModifier {
        var mk = KeyModifier()
        
        if flags.contains(.shift) {
            let _ = mk.insert(.leftShift)
            let _ = mk.insert(.rightShift)
        }
        
        if flags.contains(.option) {
            let _ = mk.insert(.leftAlt)
            let _ = mk.insert(.rightAlt)
        }
        
        if flags.contains(.control) {
            let _ = mk.insert(.leftCtrl)
            let _ = mk.insert(.rightCtrl)
        }
        
        if flags.contains(.command) {
            let _ = mk.insert(.leftMeta)
            let _ = mk.insert(.rightMeta)
        }
        
        return mk
    }
    
    func windowDidResize() {
        let originalFrame = win.frame
        let rect = win.contentRect(forFrameRect: originalFrame)
        let width = UInt16(rect.size.width)
        let height = UInt16(rect.size.height)
        eventQueue.postSizeEvent(width, height: height)
        
        // make sure both mouse button states are .Up
        eventQueue.postMouseEvent(mx, y: my, z: scroll, button: .left, state: .up)
        eventQueue.postMouseEvent(mx, y: my, z: scroll, button: .right, state: .up)
    }
}

var s_ctx: Context = Context()

func main() {
    s_ctx.run()
}
