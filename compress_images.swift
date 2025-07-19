#!/usr/bin/env swift

import Foundation
import AppKit // 需要引入 AppKit 来处理图片，这通常意味着脚本需要在 macOS 环境下运行

// 检查命令行参数
guard CommandLine.arguments.count == 3 else {
    print("使用方法: swift compress_images.swift <文件夹路径> <压缩比例>")
    print("例如: swift compress_images.swift /Users/YourName/Pictures 0.8")
    exit(1)
}

let folderPath = CommandLine.arguments[1]
guard let compressionQuality = Float(CommandLine.arguments[2]) else {
    print("错误: 压缩比例必须是0.0到1.0之间的数字。")
    exit(1)
}

guard compressionQuality >= 0.0 && compressionQuality <= 1.0 else {
    print("错误: 压缩比例必须在0.0到1.0之间。")
    exit(1)
}

let fileManager = FileManager.default
let folderURL = URL(fileURLWithPath: folderPath)

let imageExtensions = ["jpg", "jpeg", "png", "heic"] // 可以根据需要添加更多图片格式

var compressedCount = 0
var skippedCount = 0

// 遍历目录的枚举器，用于递归查找
let enumerator = fileManager.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])

print("开始压缩图片...")
print("目标文件夹: \(folderPath)")
print("压缩比例: \(compressionQuality)")
print("---")

while let fileURL = enumerator?.nextObject() as? URL {
    // 确保是文件而不是目录
    guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
          resourceValues.isRegularFile == true else {
        continue
    }

    let fileExtension = fileURL.pathExtension.lowercased()

    if imageExtensions.contains(fileExtension) {
        print("正在处理: \(fileURL.lastPathComponent) (位于: \(fileURL.deletingLastPathComponent().lastPathComponent)/)")

        guard let image = NSImage(contentsOf: fileURL) else {
            print("警告: 无法加载图片 \(fileURL.lastPathComponent)，跳过。")
            skippedCount += 1
            continue
        }

        var imageData: Data?

        if fileExtension == "png" {
            // 对于PNG，即使是无损格式，重新生成数据也可能移除一些元数据或优化
            // 但压缩比例对其文件大小影响不大，如需大幅减小PNG，需其他算法
            if let tiffRepresentation = image.tiffRepresentation,
               let imageRep = NSBitmapImageRep(data: tiffRepresentation) {
                imageData = imageRep.representation(using: .png, properties: [:])
            }
        } else { // 对于 JPG, JPEG, HEIC 等，使用 JPEG 压缩
            if let tiffRepresentation = image.tiffRepresentation,
               let imageRep = NSBitmapImageRep(data: tiffRepresentation) {
                imageData = imageRep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
            }
        }

        if let compressedData = imageData {
            do {
                // 直接写入覆盖原有文件
                try compressedData.write(to: fileURL, options: .atomic) // 使用 .atomic 写入保证原子性，避免数据损坏
                print("已成功压缩并覆盖: \(fileURL.lastPathComponent)")
                compressedCount += 1
            } catch {
                print("错误: 无法覆盖图片 \(fileURL.lastPathComponent): \(error.localizedDescription)")
                skippedCount += 1
            }
        } else {
            print("警告: 无法获取图片数据或压缩 \(fileURL.lastPathComponent)，跳过。")
            skippedCount += 1
        }
    }
}

print("---")
print("压缩完成！")
print("成功压缩并覆盖 \(compressedCount) 张图片。")
print("跳过 \(skippedCount) 张图片。")
