//
//  File.swift
//  
//
//  Created by Harlan Haskins on 9/27/23.
//

import Foundation
import AppKit
import QOIReference
import QOI

func convertImage(at url: URL) throws {
    let image = NSImage(contentsOf: url)!
    let imageRep = image.representations.first { $0 is NSBitmapImageRep } as! NSBitmapImageRep
    let pixels = imageRep.bitmapData!
    let baseName = url.deletingPathExtension().lastPathComponent
    do {
        let length = imageRep.bytesPerRow * Int(imageRep.size.height)
        let start = CACurrentMediaTime()
        let desc = try QOIDescription(width: UInt32(imageRep.size.width), height: UInt32(imageRep.size.height), includesAlpha: true, colorSpace: .sRGB)
        let output = qoiEncode(
            UnsafeBufferPointer(start: pixels, count: length),
            description: desc)
        let end = CACurrentMediaTime()
        print("swift: \(end - start)")
        let newFilename = url.deletingPathExtension().appendingPathExtension("qoi")
        try Data(output).write(to: newFilename)
    }

    do {
        let start = CACurrentMediaTime()
        var desc = qoi_desc(width: UInt32(imageRep.size.width), height: UInt32(imageRep.size.height), channels: 4, colorspace: 0)
        var length: Int32 = 0
        let referenceOutput = qoi_encode(UnsafeRawPointer(pixels), &desc, &length)!
        let end = CACurrentMediaTime()
        print("c: \(end - start)")

        let newFilename = url.deletingLastPathComponent().appendingPathComponent("\(baseName)_reference.qoi")
        try Data(bytes: referenceOutput, count: Int(length)).write(to: newFilename)
    }
}

let arg = CommandLine.arguments[1]
try convertImage(at: URL(fileURLWithPath: arg))
