import Foundation

public struct LocalPresetModelURLs: Sendable {
    public let speechModelURL: URL
    public let translationModelURL: URL
}

public struct LocalModelDownloadProgress: Sendable {
    public enum Stage: String, Sendable {
        case speech
        case translation

        var label: String {
            switch self {
            case .speech:
                return "Speech model"
            case .translation:
                return "Translation model"
            }
        }
    }

    public let preset: LocalRealtimePreset
    public let stage: Stage
    public let fractionCompleted: Double
    public let bytesWritten: Int64
    public let totalBytes: Int64?
}

public actor LocalModelStore {
    public static let shared = LocalModelStore()

    private let rootDirectory: URL

    public init(fileManager: FileManager = .default) {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        rootDirectory = applicationSupport
            .appendingPathComponent("RealtimeInterpretationDemo", isDirectory: true)
            .appendingPathComponent("LocalModels", isDirectory: true)
    }

    public func isReady(for preset: LocalRealtimePreset) -> Bool {
        let urls = presetURLs(for: preset)
        return fileExists(at: urls.speechModelURL) && fileExists(at: urls.translationModelURL)
    }

    public func presetURLs(for preset: LocalRealtimePreset) -> LocalPresetModelURLs {
        LocalPresetModelURLs(
            speechModelURL: localURL(
                kindDirectory: "whisper",
                fileName: preset.speechModel.fileName
            ),
            translationModelURL: localURL(
                kindDirectory: "translator",
                fileName: preset.translationModel.fileName
            )
        )
    }

    public func ensureDownloaded(
        for preset: LocalRealtimePreset,
        progress: @Sendable @escaping (LocalModelDownloadProgress) async -> Void
    ) async throws -> LocalPresetModelURLs {
        let urls = presetURLs(for: preset)

        if !fileExists(at: urls.speechModelURL) {
            try await download(
                assetName: preset.speechModel.displayName,
                stage: .speech,
                preset: preset,
                remoteURL: preset.speechModel.downloadURL,
                destinationURL: urls.speechModelURL,
                progress: progress
            )
        }

        if !fileExists(at: urls.translationModelURL) {
            try await download(
                assetName: preset.translationModel.displayName,
                stage: .translation,
                preset: preset,
                remoteURL: preset.translationModel.downloadURL,
                destinationURL: urls.translationModelURL,
                progress: progress
            )
        }

        return urls
    }

    private func localURL(kindDirectory: String, fileName: String) -> URL {
        rootDirectory
            .appendingPathComponent(kindDirectory, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private func fileExists(at url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
    }

    private func createParentDirectory(for url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func download(
        assetName: String,
        stage: LocalModelDownloadProgress.Stage,
        preset: LocalRealtimePreset,
        remoteURL: URL,
        destinationURL: URL,
        progress: @Sendable @escaping (LocalModelDownloadProgress) async -> Void
    ) async throws {
        try createParentDirectory(for: destinationURL)

        let tempURL = destinationURL.appendingPathExtension("downloading")
        try? FileManager.default.removeItem(at: tempURL)
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)

        let (bytes, response) = try await URLSession.shared.bytes(from: remoteURL)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw InterpretationError.modelDownloadFailed("\(assetName) returned HTTP \(httpResponse.statusCode).")
        }

        let expectedSize = response.expectedContentLength > 0 ? response.expectedContentLength : nil
        let handle = try FileHandle(forWritingTo: tempURL)
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: tempURL)
        }

        var buffer = Data()
        var written: Int64 = 0
        let chunkSize = 1 << 20

        for try await byte in bytes {
            try Task.checkCancellation()
            buffer.append(byte)
            if buffer.count >= chunkSize {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                let fraction = expectedSize.map { min(Double(written) / Double($0), 1.0) } ?? 0
                await progress(
                    LocalModelDownloadProgress(
                        preset: preset,
                        stage: stage,
                        fractionCompleted: fraction,
                        bytesWritten: written,
                        totalBytes: expectedSize
                    )
                )
            }
        }

        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
        }

        try handle.synchronize()
        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)

        await progress(
            LocalModelDownloadProgress(
                preset: preset,
                stage: stage,
                fractionCompleted: 1,
                bytesWritten: written,
                totalBytes: expectedSize
            )
        )
    }
}
