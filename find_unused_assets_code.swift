#!/usr/bin/env swift

import Foundation

// --- 配置区域 ---
// 要检查的 Swift 项目根路径

// 检查命令行参数
guard CommandLine.arguments.count == 2 else {
    print("使用方法: swift find_unused_assets_code.swift <工程路径> ")
    print("例如: swift find_unused_assets_code.swift /Users/YourName/YourProject")
    exit(1)
}

let projectRootPath = CommandLine.arguments[1] // <--- 替换为你的项目路径

// 要检查的图片文件扩展名
let imageExtensions = ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "bmp", "svg"]

// 要搜索引用的文件扩展名 (代码文件和Interface Builder文件)
let searchExtensions = ["swift", "xib", "storyboard"]

// 排除的文件夹或文件模式 (基于路径，大小写不敏感，例如 ["Pods", "Carthage", ".git"])
let excludedPaths: [String] = ["Pods", "Carthage", ".git", "build"]

// --- 配置区域结束 ---

// MARK: - 文件管理器和URL
let fileManager = FileManager.default
let projectRootURL = URL(fileURLWithPath: projectRootPath)

guard fileManager.fileExists(atPath: projectRootPath) else {
    print("错误: 项目路径不存在 - \(projectRootPath)")
    exit(1)
}

print("---")
print("未引用资源代码检测...")
print("项目路径: \(projectRootPath)")
print("---")

// MARK: - 辅助函数
func getFileContents(at url: URL) -> String? {
    do {
        return try String(contentsOf: url, encoding: .utf8)
    } catch {
         print("警告: 无法读取文件 \(url.lastPathComponent) - \(error.localizedDescription)")
        return nil
    }
}

// 检查路径是否应被排除
func shouldExcludePath(_ url: URL) -> Bool {
    let path = url.path.lowercased()
    for excluded in excludedPaths {
        if path.contains(excluded.lowercased()) {
            return true
        }
    }
    return false
}

// MARK: - 1. 查找未被引用的图片

print("## 1. 检测未被引用的图片")
print("---")

var allImageNames: [String] = []
var allImageFileURLs: [URL] = []
var allSearchableFileContents: String = "" // 合并所有可搜索文件的内容
// 用于统计 .imageset 名称的出现次数，以找出重名
var imageSetNamesCount: [String: Int] = [:]

// 添加图片
func addImageName(_ imageName: String) {
    if !allImageNames.contains(imageName) {
        allImageNames.append(imageName)
    } else {
        imageSetNamesCount[imageName] = (imageSetNamesCount[imageName] ?? 1) + 1
    }
}

// 收集所有图片文件
let imageEnumerator = fileManager.enumerator(at: projectRootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
while let url = imageEnumerator?.nextObject() as? URL {
    if shouldExcludePath(url) { continue }

    if imageExtensions.contains(url.pathExtension.lowercased()) {
        allImageFileURLs.append(url)
        var imageName = url.deletingPathExtension().lastPathComponent
        if url.path.contains(".imageset") {
            for component in url.pathComponents {
                if component.lowercased().hasSuffix(".imageset") {
                    imageName = (component as NSString).deletingPathExtension
                }
            }
        } 
        addImageName(imageName)
    }
}

// 同名图片输出
if !imageSetNamesCount.keys.isEmpty {
    print("### 1.1 发现同名图片")
    for (name, count) in imageSetNamesCount {
        print("    - \(name): \(count) 个")
    }
    print("---")
}

// 收集所有可搜索文件的内容
let searchFileEnumerator = fileManager.enumerator(at: projectRootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
while let url = searchFileEnumerator?.nextObject() as? URL {
    if shouldExcludePath(url) { continue }

    if searchExtensions.contains(url.pathExtension.lowercased()) {
        if let content = getFileContents(at: url) {
            allSearchableFileContents.append(content)
        }
    }
}

var unreferencedImages: [String] = []

for imageName in allImageNames {
    // 简单的文本搜索，查找 UIImage(named: "ImageName"), <image name="ImageName"> 等
    let pattern1 = "\"\(imageName)\"" // 用于代码中的字符串引用
    let pattern2 = "name=\"\(imageName)\"" // 用于XML文件中的引用 (xib, storyboard)
    if !allSearchableFileContents.contains(pattern1) && !allSearchableFileContents.contains(pattern2) {
        unreferencedImages.append(imageName)
    }
}

print("### 1.2 图片引用检测结果")

if unreferencedImages.isEmpty {
    print("  太棒了！没有发现明显的未引用图片。")
} else {
    print("  发现以下可能未被引用的图片名称（请手动检查）：")
    for imageName in unreferencedImages.sorted() {
        print("    - \(imageName)")
        // 如果想知道具体哪个文件是未引用的图片文件，可以根据 unreferencedImages 去 allImageFileURLs 里找
        if let filePath = allImageFileURLs.first(where: { $0.deletingPathExtension().lastPathComponent == imageName })?.path {
            print("      (文件路径: \(filePath))")
        } else if let assetPath = allImageFileURLs.first(where: { $0.pathExtension.lowercased() == "xcassets" && ($0.appendingPathComponent("\(imageName).imageset").path.count > 0 || fileManager.fileExists(atPath: $0.appendingPathComponent("\(imageName).imageset").path))})?.appendingPathComponent("\(imageName).imageset").path {
             print("      (Asset Catalog路径: \(assetPath))")
        }
    }
}

print("---")

// MARK: - 2. 查找未被引用的类 (包括 Structs 和 Enums)

print("## 2. 检测未被引用的类/结构体/枚举")
print("---")

var allClassDeclarations: [String: URL] = [:] // [类名: 声明该类的文件URL]
var allSearchableSwiftContents: String = "" // 合并所有 Swift 文件的内容

// 遍历所有 Swift 文件，收集所有类/结构体/枚举声明
let swiftFileEnumerator = fileManager.enumerator(at: projectRootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
while let url = swiftFileEnumerator?.nextObject() as? URL {
    if shouldExcludePath(url) { continue }

    if url.pathExtension.lowercased() == "swift" {
        if let content = getFileContents(at: url) {
            allSearchableSwiftContents.append(content)

            // 简单的正则匹配 class/struct/enum 名称
            // 匹配 class/struct/enum Foo 或 class/struct/enum Foo: Bar
            let regex = try? NSRegularExpression(pattern: "(?:class|struct|enum)\\s+([A-Z_][a-zA-Z0-9_]*)(?:\\s*[:{])?", options: [])
            regex?.enumerateMatches(in: content, options: [], range: NSRange(content.startIndex..., in: content)) { (match, _, _) in
                if let match = match, match.numberOfRanges > 1 {
                    let classNameRange = match.range(at: 1)
                    if let range = Range(classNameRange, in: content) {
                        let className = String(content[range])
                        allClassDeclarations[className] = url
                    }
                }
            }
        }
    } else if searchExtensions.contains(url.pathExtension.lowercased()) && url.pathExtension.lowercased() != "swift" {
        // 将非 Swift 的可搜索文件内容也加入，以便查找类在 Interface Builder 中的引用
        if let content = getFileContents(at: url) {
            allSearchableSwiftContents.append(content)
        }
    }
}

var potentialUnreferencedClasses: [String: URL] = [:] // [类名: 声明该类的文件URL]

for (className, declaringURL) in allClassDeclarations {
    // 排除 Swift 标准库和系统框架中常见的类型，这些通常不需要混淆
    if className.hasPrefix("NS") || className.hasPrefix("UI") || className.hasPrefix("CG") ||
       className.hasPrefix("CA") || className.hasPrefix("KF") || // 例如 Kingfisher
       ["String", "Int", "Double", "Bool", "Array", "Dictionary", "Set", "Optional", "Result", "Date", "URL", "Error", "Codable", "Decodable", "Encodable"].contains(className) {
        continue
    }

    // 在所有 Swift 和 IB 文件中搜索该类的引用
    // 这里搜索的模式需要小心，以避免误伤注释或字符串
    // 寻找 `class_name`、`class_name(`、`class_name.` 等形式
    let searchPattern1 = "\(className)(" // 作为类型引用，例如 `let myVar: MyClass`
    let searchPattern2 = "\(className).self" // 例如 `MyClass.self`
    let searchPattern3 = "\(className)(" // 作为构造函数调用
    let searchPattern4 = "customClass=\"\(className)\"" // 用于 Storyboard/XIB 中的引用

    // 我们要确保找到的不是其自身的声明
    var referencesFound = false

    // 检查在其他文件中的引用
    for (_, url) in allClassDeclarations where url != declaringURL {
        if let content = getFileContents(at: url) {
            if content.contains(searchPattern1) || content.contains(searchPattern2) || content.contains(searchPattern3) {
                referencesFound = true
                break
            }
        }
    }

    // 检查在 xib/storyboard 文件中的引用
    if !referencesFound {
        let ibFileEnumerator = fileManager.enumerator(at: projectRootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let url = ibFileEnumerator?.nextObject() as? URL {
            if shouldExcludePath(url) { continue }
            if url.pathExtension.lowercased() == "xib" || url.pathExtension.lowercased() == "storyboard" {
                if let content = getFileContents(at: url) {
                    if content.contains(searchPattern4) {
                        referencesFound = true
                        break
                    }
                }
            }
        }
    }

    // 如果在该类自身的声明文件之外没有找到引用，则认为是潜在未引用
    if !referencesFound {
        potentialUnreferencedClasses[className] = declaringURL
    }
}

if potentialUnreferencedClasses.isEmpty {
    print("  太棒了！没有发现明显的未引用类/结构体/枚举。")
} else {
    print("  发现以下可能未被引用的类/结构体/枚举（强烈建议手动检查引用链）：")
    for (className, declaringURL) in potentialUnreferencedClasses.sorted(by: { $0.key < $1.key }) {
        print("    - \(className) (声明于: \(declaringURL.lastPathComponent))")
    }
    print("\n  注意：如果 A 引用了 B 但 A 未被任何外部类引用，本脚本仅能标记 A 为未引用。您需要手动检查 A 的引用情况，如果 A 确实未被引用，那么 B 也应被视为未引用。")
}

print("---")
print("检测完成。请根据结果仔细进行人工检查和验证。")
print("在删除任何文件或代码之前，请务必进行项目备份。")
