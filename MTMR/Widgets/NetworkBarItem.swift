//
//  NetworkBarItem.swift
//  MTMR
//
//  Created by Anton Palgunov on 23/02/2019.
//  Copyright © 2019 Anton Palgunov. All rights reserved.
//

import Foundation

class NetworkBarItem: CustomButtonTouchBarItem, Widget, TearDownable {
    private var bandwidthProcess: Process?
    private var dataObserver: NSObjectProtocol?

    func tearDown() {
        if let observer = dataObserver { NotificationCenter.default.removeObserver(observer) }
        dataObserver = nil
        bandwidthProcess?.terminate()
        bandwidthProcess = nil
    }

    static var name: String = "network"
    static var identifier: String = "com.toxblh.mtmr.network"
    
    private let flip: Bool
    private let units: String
    
    init(identifier: NSTouchBarItem.Identifier, flip: Bool = false, units: String) {
        self.flip = flip
        self.units = units
        super.init(identifier: identifier, title: " ")
        startMonitoringProcess()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startMonitoringProcess() {
        var pipe: Pipe
        var outputHandle: FileHandle
        var dSpeed: UInt64?
        var uSpeed: UInt64?
        var curr: Array<Substring>?
        var dataAvailable: NSObjectProtocol?

        pipe = Pipe()
        bandwidthProcess = Process()
        bandwidthProcess?.launchPath = "/usr/bin/env"
        bandwidthProcess?.arguments = ["netstat", "-w1", "-l", "en0"]
        bandwidthProcess?.standardOutput = pipe

        outputHandle = pipe.fileHandleForReading
        outputHandle.waitForDataInBackgroundAndNotify(forModes: [RunLoop.Mode.common])

        dataAvailable = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSFileHandleDataAvailable,
            object: outputHandle,
            queue: nil
        ) { [weak self] _ -> Void in
            guard let self = self else { return }
            let data = pipe.fileHandleForReading.availableData
            if data.count > 0 {
                if let str = NSString(data: data, encoding: String.Encoding.utf8.rawValue) {
                    curr = [""]
                    curr = str
                        .replacingOccurrences(of: "  ", with: " ")
                        .split(separator: " ")
                    if curr == nil || (curr?.count)! < 6 {} else {
                        if Int64(curr![2]) == nil {} else {
                            dSpeed = UInt64(curr![2])
                            uSpeed = UInt64(curr![5])

                            self.setTitle(up: self.getHumanizeSize(speed: uSpeed!), down: self.getHumanizeSize(speed: dSpeed!))
                        }
                    }
                }
                outputHandle.waitForDataInBackgroundAndNotify()
            } else if let dataAvailable = dataAvailable {
                NotificationCenter.default.removeObserver(dataAvailable)
            }
        }

        var dataReady: NSObjectProtocol?
        dataReady = NotificationCenter.default.addObserver(
            forName: Process.didTerminateNotification,
            object: outputHandle,
            queue: nil
        ) { _ -> Void in
            print("Task terminated!")
            if let observer = dataReady {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        dataObserver = dataAvailable
        bandwidthProcess?.launch()
    }

    func getHumanizeSize(speed: UInt64) -> String {
        let humanText: String
        
        func speedB(speed: UInt64)-> String {
            return String(format: "%.0f", Double(speed)) + " B/s"
        }
        
        func speedKB(speed: UInt64)-> String {
            return String(format: "%.1f", Double(speed) / 1024) + " KB/s"
        }
        
        func speedMB(speed: UInt64)-> String {
            return String(format: "%.1f", Double(speed) / (1024 * 1024)) + " MB/s"
        }
        
        func speedGB(speed: UInt64)-> String {
            return String(format: "%.2f", Double(speed) / (1024 * 1024 * 1024)) + " GB/s"
        }
        
        switch self.units {
        case "B/s":
            humanText = speedB(speed: speed)
        case "KB/s":
            humanText = speedKB(speed: speed)
        case "MB/s":
            humanText = speedMB(speed: speed)
        case "GB/s":
            humanText = speedGB(speed: speed)
        default:
            if speed < 1024 {
                humanText = speedB(speed: speed)
            } else if speed < (1024 * 1024) {
                humanText = speedKB(speed: speed)
            } else if speed < (1024 * 1024 * 1024) {
                humanText = speedMB(speed: speed)
            } else {
                humanText = speedGB(speed: speed)
            }
        }

        return humanText
    }
    
    func appendUpSpeed(appendString: NSMutableAttributedString, up: String, titleFont: NSFont, newStr: Bool = false) {
        appendString.append(NSMutableAttributedString(
            string: newStr ? "\n↑" : "↑",
            attributes: [
                NSAttributedString.Key.foregroundColor: NSColor.systemBlue,
                NSAttributedString.Key.font: titleFont,
                ]))
        
        appendString.append(NSMutableAttributedString(
            string: up,
            attributes: [
                NSAttributedString.Key.font: titleFont,
                ]))
    }
    
    func appendDownSpeed(appendString: NSMutableAttributedString, down: String, titleFont: NSFont, newStr: Bool = false) {
        appendString.append(NSMutableAttributedString(
            string: newStr ? "\n↓" : "↓",
            attributes: [
                NSAttributedString.Key.foregroundColor: NSColor.systemRed,
                NSAttributedString.Key.font: titleFont,
                ]))
            
            appendString.append(NSMutableAttributedString(
                string: down,
                attributes: [
                    NSAttributedString.Key.font: titleFont
                ]))
    }
    
    func setTitle(up: String, down: String) {
        let titleFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: NSFont.Weight.regular)
        
        let newTitle: NSMutableAttributedString = NSMutableAttributedString(string: "")
        
        if (self.flip) {
            appendUpSpeed(appendString: newTitle, up: up, titleFont: titleFont)
            appendDownSpeed(appendString: newTitle, down: down, titleFont: titleFont, newStr: true)
        } else {
            appendDownSpeed(appendString: newTitle, down: down, titleFont: titleFont)
            appendUpSpeed(appendString: newTitle, up: up, titleFont: titleFont, newStr: true)
        }
        
        
        // Two lines must fit the 30pt bar: pin the line height instead of using
        // the font's default leading, which pushes the second line off the bottom.
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 13
        paragraph.maximumLineHeight = 13
        paragraph.alignment = .left
        let range = NSRange(location: 0, length: newTitle.length)
        newTitle.addAttribute(.paragraphStyle, value: paragraph, range: range)
        newTitle.addAttribute(.baselineOffset, value: -1, range: range)

        self.attributedTitle = newTitle
    }
}
