#!/usr/bin/env swift

import Foundation

// --- 配置区域 ---
// 要混淆的 Swift 项目根路径
let projectRootPath = "/Users/YourName/YourProject" // <--- 替换为你的项目路径

// 是否启用类名前缀混淆
let enableClassPrefixObfuscation = true
// 要添加的类名前缀 (例如 "Obf_")
let classPrefix = "Obf_"

// 是否启用方法名替换混淆
let enableMethodNameObfuscation = true
// 方法名映射表: [原始方法名: 混淆后的方法名]
// 注意: 键值必须是完整的方法签名的一部分，以提高匹配准确性，但仍有风险。
let methodRenamingMap: [String: String] = [
    "func setupUI()": "func configureViews()",
    "private func fetchData(completion: @escaping (Result<Data, Error>) -> Void)": "private func retrieveData(callback: @escaping (Result<Data, Error>) -> Void)",
    "func processData()": "func handleInformation()"
]
// --- 配置区域结束 ---


// MARK: - 脚本核心逻辑

let fileManager = FileManager.default
let projectRootURL = URL(fileURLWithPath: projectRootPath)

guard fileManager.fileExists(atPath: projectRootPath) else {
    print("错误: 项目路径不存在 - \(projectRootPath)")
    exit(1)
}

print("---")
print("Swift 代码混淆脚本启动...")
print("项目路径: \(projectRootPath)")
print("---")

var processedFilesCount = 0
var obfuscationSummary: [String: [String]] = [:] // 用于记录每个文件中的混淆操作

// 遍历项目目录下的所有 .swift 文件
let enumerator = fileManager.enumerator(at: projectRootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])

while let fileURL = enumerator?.nextObject() as? URL {
    guard fileURL.pathExtension.lowercased() == "swift" else {
        continue
    }

    do {
        var fileContent = try String(contentsOf: fileURL, encoding: .utf8)
        var hasChanges = false
        var currentFileChanges: [String] = []

        // 1. 类名前缀混淆
        if enableClassPrefixObfuscation {
            // 匹配 class Foo, struct Bar, enum Baz 形式的声明
            // 这只是一个简单的正则，对于复杂情况可能不足
            let classRegex = try NSRegularExpression(pattern: "(class|struct|enum)\\s+([A-Z][a-zA-Z0-9_]+)", options: [])
            let originalContent = fileContent
            var replacedRanges: [NSRange] = [] // 记录已替换的范围，避免重复替换或交叉替换

            // 第一次遍历：收集所有需要替换的类名和它们的原始名称
            var classesToObfuscate: [(original: String, obfuscated: String)] = []
            classRegex.enumerateMatches(in: fileContent, options: [], range: NSRange(fileContent.startIndex..., in: fileContent)) { (match, _, _) in
                if let match = match, match.numberOfRanges > 2 {
                    let classNameRange = match.range(at: 2)
                    if let range = Range(classNameRange, in: fileContent) {
                        let originalClassName = String(fileContent[range])
                        let obfuscatedClassName = classPrefix + originalClassName
                        classesToObfuscate.append((originalClassName, obfuscatedClassName))
                    }
                }
            }

            // 第二次遍历：执行替换操作
            // 为了正确处理替换后的字符串长度变化，从后往前替换
            for (originalName, obfuscatedName) in classesToObfuscate.sorted(by: { $0.original.count > $1.original.count }) { // 优先替换更长的名称，避免部分匹配
                // 替换所有引用
                let tempContent = fileContent
                let replaced = tempContent.replacingOccurrences(of: originalName, with: obfuscatedName)
                if replaced != tempContent {
                    fileContent = replaced
                    hasChanges = true
                    currentFileChanges.append("类名: \(originalName) -> \(obfuscatedName)")
                }
            }
        }

        // 2. 方法名替换混淆
        if enableMethodNameObfuscation {
            for (originalMethod, obfuscatedMethod) in methodRenamingMap {
                // 直接替换字符串，需要确保 originalMethod 足够独特以避免误伤
                let tempContent = fileContent
                let replaced = tempContent.replacingOccurrences(of: originalMethod, with: obfuscatedMethod)
                if replaced != tempContent {
                    fileContent = replaced
                    hasChanges = true
                    currentFileChanges.append("方法: '\(originalMethod)' -> '\(obfuscatedMethod)'")
                }
            }
        }

        if hasChanges {
            try fileContent.write(to: fileURL, atomically: true, encoding: .utf8)
            processedFilesCount += 1
            obfuscationSummary[fileURL.lastPathComponent] = currentFileChanges
            print("  处理文件: \(fileURL.lastPathComponent)")
        }

    } catch {
        print("错误: 处理文件 \(fileURL.lastPathComponent) 失败 - \(error.localizedDescription)")
    }
}

print("---")
print("混淆完成！")
print("共处理 \(processedFilesCount) 个 Swift 文件。")

if processedFilesCount > 0 {
    print("\n混淆详情:")
    for (fileName, changes) in obfuscationSummary {
        print("  \(fileName):")
        for change in changes {
            print("    - \(change)")
        }
    }
}

print("---")
print("重要提示：请务必在运行脚本后彻底测试您的项目，以确保功能没有受损。")
print("强烈建议在运行此脚本前备份您的整个项目。")
