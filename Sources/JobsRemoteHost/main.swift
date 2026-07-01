//
//  main.swift
//  JobsRemoteHost
//
//  Created by Jobs on 2026年6月30日，星期二.
//

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()

app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
