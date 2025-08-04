#!/usr/bin/env swift

import AVFoundation
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers // 新增导入以使用UTType

// 检查URL是否为网络URL
func isNetworkURL(_ url: URL) -> Bool {
    return url.scheme == "http" || url.scheme == "https"
}

// 异步获取视频第一帧（支持网络流和本地文件）
func getFirstFrameAsync(from url: URL, completion: @escaping (CGImage?) -> Void) {
    // 使用AVURLAsset替代已弃用的AVAsset(url:)
    let asset = AVURLAsset(url: url)
    
    // 移除了不可用的AVAssetResourceLoader相关代码
    Task {
        // 检查资产是否可以播放
        let isPlayable = try await asset.load(.isPlayable)
        if isPlayable {
            // 移除self，在全局函数中不需要
            extractFirstFrame(from: asset, completion: completion)
        } else {
            print("无法处理视频资源, 视频无法播放")
            completion(nil)
        }
    }
}

// 从AVAsset提取第一帧
private func extractFirstFrame(from asset: AVAsset, completion: @escaping (CGImage?) -> Void) {
    let imageGenerator = AVAssetImageGenerator(asset: asset)
    imageGenerator.appliesPreferredTrackTransform = true
    imageGenerator.maximumSize = CGSize(width: 1024, height: 1024) // 限制最大尺寸
    
    // 设置要获取的时间点（第一帧）
    let time = CMTimeMake(value: 0, timescale: 1) // 使用1/30秒避免空帧
    
    imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { 
        (requestedTime, cgImage, actualTime, result, error) in
        
        if result == .succeeded, let cgImage = cgImage {
            completion(cgImage)
        } else {
            print("获取视频帧失败: \(error?.localizedDescription ?? "未知错误")")
            completion(nil)
        }
    }
}

// 保存CGImage到文件
func saveCGImage(_ image: CGImage, to url: URL) -> Bool {
    // 使用UTType.png替代已弃用的kUTTypePNG
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        print("无法创建图像目标")
        return false
    }
    
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
}

// 处理结果的辅助函数
func handleResult(image: CGImage?) {
    if let firstFrame = image {
        print("成功获取视频第一帧")
        
        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let outputURL = documentsDirectory.appendingPathComponent("first_frame.png")
            
            if saveCGImage(firstFrame, to: outputURL) {
                print("图片已保存到: \(outputURL.path)")
            } else {
                print("保存图片失败")
            }
        }
    } else {
        print("无法获取视频第一帧")
    }
    exit(0)
}

// 使用示例
if CommandLine.arguments.count > 1 {
    let urlString = CommandLine.arguments[1]
    
    guard let url = URL(string: urlString) else {
        print("无效的URL格式")
        exit(1)
    }
    
    // 处理本地路径
    if !isNetworkURL(url), url.scheme == nil {
        let fileURL = URL(fileURLWithPath: urlString)
        print("正在处理本地视频: \(fileURL.path)")
        getFirstFrameAsync(from: fileURL) { handleResult(image: $0) }
    } else {
        print("正在处理网络视频流: \(url.absoluteString)")
        getFirstFrameAsync(from: url) { handleResult(image: $0) }
    }
} else {
    print("请提供视频URL或本地路径作为参数")
    print("用法:")
    print("  本地文件: swift VideoFrameExtractor.swift /path/to/your/video.mp4")
    print("  网络文件: swift VideoFrameExtractor.swift https://example.com/video.mp4")
    exit(1)
}

// 等待异步操作完成
RunLoop.main.run(until: Date().addingTimeInterval(30))
