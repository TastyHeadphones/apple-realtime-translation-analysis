import Foundation
@preconcurrency import LlamaSwift

@available(iOS 26.0, *)
public actor LocalTranslationService {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var batch: llama_batch?
    private var configuredModelURL: URL?
    private var backendInitialized = false
    private let maxTokenCount: Int = 768
    private let maxGeneratedTokens: Int = 192

    public init() {}

    public func configure(modelURL: URL) throws {
        if configuredModelURL == modelURL, model != nil, context != nil, vocab != nil, batch != nil {
            return
        }

        cleanup()
        if !backendInitialized {
            llama_backend_init()
            backendInitialized = true
        }

        let modelParams = llama_model_default_params()
        guard let loadedModel = llama_model_load_from_file(modelURL.path, modelParams) else {
            throw InterpretationError.translationModelLoadFailed("Failed to load \(modelURL.lastPathComponent).")
        }

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(maxTokenCount)
        contextParams.n_batch = UInt32(maxTokenCount)
        contextParams.n_threads = Int32(max(1, ProcessInfo.processInfo.processorCount))
        contextParams.n_threads_batch = Int32(max(1, ProcessInfo.processInfo.processorCount))
        contextParams.embeddings = false

        guard let loadedContext = llama_init_from_model(loadedModel, contextParams) else {
            llama_model_free(loadedModel)
            throw InterpretationError.translationModelLoadFailed("Failed to create llama context.")
        }

        let loadedVocab = llama_model_get_vocab(loadedModel)
        let loadedBatch = llama_batch_init(Int32(maxTokenCount), 0, 1)

        model = loadedModel
        context = loadedContext
        vocab = loadedVocab
        batch = loadedBatch
        configuredModelURL = modelURL
    }

    public func translate(
        _ text: String,
        source: Locale.Language,
        target: Locale.Language,
        onPartial: (@Sendable (String) async -> Void)? = nil
    ) async throws -> String {
        guard let context, let vocab, let batchTemplate = batch else {
            throw InterpretationError.translationModelLoadFailed("Local translator is not configured.")
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        resetContext(context)

        let prompt = translationPrompt(
            sourceText: trimmed,
            sourceLabel: readableLabel(for: source),
            targetLabel: readableLabel(for: target)
        )

        let promptTokens = tokenize(prompt, vocab: vocab)
        guard !promptTokens.isEmpty else {
            throw InterpretationError.translationFailed("Prompt tokenization failed.")
        }

        var batch = batchTemplate
        var tokenCursor = Int32(promptTokens.count)

        prepareBatch(
            &batch,
            tokens: promptTokens,
            promptTokenCount: promptTokens.count,
            tokenCursor: tokenCursor,
            vocab: vocab
        )

        guard llama_decode(context, batch) == 0 else {
            throw InterpretationError.translationFailed("Failed to evaluate the prompt.")
        }

        var output = ""
        var generatedTokens = 0

        while generatedTokens < maxGeneratedTokens {
            guard let logits = llama_get_logits_ith(context, batch.n_tokens - 1) else {
                throw InterpretationError.translationFailed("Failed to read model logits.")
            }

            let nextToken = argmaxToken(from: logits, vocab: vocab)
            if nextToken == llama_vocab_eos(vocab) {
                break
            }

            let piece = decode(token: nextToken, vocab: vocab)
            if !piece.isEmpty {
                output += piece
                if let onPartial {
                    await onPartial(output.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }

            batch.n_tokens = 1
            batch.token[0] = nextToken
            batch.pos[0] = tokenCursor
            batch.n_seq_id[0] = 1
            if let seqIds = batch.seq_id, let seqId = seqIds[0] {
                seqId[0] = 0
            }
            batch.logits[0] = 1

            guard llama_decode(context, batch) == 0 else {
                throw InterpretationError.translationFailed("Model decoding failed.")
            }

            tokenCursor += 1
            generatedTokens += 1

            if output.contains("<|im_end|>") {
                break
            }
        }

        let cleaned = output
            .replacingOccurrences(of: "<|im_end|>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }

    private func translationPrompt(sourceText: String, sourceLabel: String, targetLabel: String) -> String {
        """
        <|im_start|>system
        You are a simultaneous interpreter with low latency.
        Translate user text into the requested target language.
        Output only the translation.
        Preserve meaning, names, numbers, punctuation, and speaker intent.
        Keep the translation concise and natural.
        If the input is a fragment, translate the fragment directly.
        Never add explanations, labels, bullets, or quotes.
        <|im_end|>
        <|im_start|>user
        Source language: \(sourceLabel)
        Target language: \(targetLabel)

        Translate the source text into the target language.
        Output only the translation.

        Source text:
        \(sourceText)
        <|im_end|>
        <|im_start|>assistant
        """
    }

    private func tokenize(_ text: String, vocab: OpaquePointer) -> [llama_token] {
        let utf8Count = text.utf8.count
        let maxTokenCount = utf8Count + 16
        var tokens = [llama_token](repeating: 0, count: maxTokenCount)
        let tokenCount = llama_tokenize(
            vocab,
            text,
            Int32(utf8Count),
            &tokens,
            Int32(maxTokenCount),
            true,
            true
        )

        guard tokenCount > 0 else { return [] }
        return Array(tokens.prefix(Int(tokenCount)))
    }

    private func prepareBatch(
        _ batch: inout llama_batch,
        tokens: [llama_token],
        promptTokenCount: Int,
        tokenCursor: Int32,
        vocab: OpaquePointer
    ) {
        batch.n_tokens = Int32(tokens.count)

        for index in tokens.indices {
            batch.token[index] = tokens[index]
            batch.pos[index] = Int32(index)
            batch.n_seq_id[index] = 1
            if let seqIds = batch.seq_id, let seqId = seqIds[index] {
                seqId[0] = 0
            }
            batch.logits[index] = index == promptTokenCount - 1 ? 1 : 0
        }

        _ = tokenCursor
        _ = vocab
    }

    private func argmaxToken(from logits: UnsafeMutablePointer<Float>, vocab: OpaquePointer) -> llama_token {
        let vocabSize = Int(llama_vocab_n_tokens(vocab))
        var bestIndex = 0
        var bestValue = logits[0]

        if vocabSize > 1 {
            for index in 1..<vocabSize {
                let value = logits[index]
                if value > bestValue {
                    bestValue = value
                    bestIndex = index
                }
            }
        }

        return llama_token(bestIndex)
    }

    private func decode(token: llama_token, vocab: OpaquePointer) -> String {
        var bufferLength = 16
        var buffer: [CChar] = .init(repeating: 0, count: bufferLength)
        var length = Int(llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false))
        guard length != 0 else { return "" }

        if length < 0 {
            bufferLength = -length
            buffer = .init(repeating: 0, count: bufferLength)
            length = Int(llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false))
            guard length > 0 else { return "" }
        }

        let validBuffer = Array(buffer.prefix(length))
        let bytes = validBuffer.map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }

    private func resetContext(_ context: OpaquePointer) {
        llama_memory_seq_rm(llama_get_memory(context), -1, -1, -1)
    }

    private func cleanup() {
        if let batch {
            llama_batch_free(batch)
            self.batch = nil
        }

        if let context {
            llama_free(context)
            self.context = nil
        }

        if let model {
            llama_model_free(model)
            self.model = nil
        }

        if backendInitialized {
            llama_backend_free()
            backendInitialized = false
        }

        vocab = nil
        configuredModelURL = nil
    }

    private func readableLabel(for language: Locale.Language) -> String {
        let identifier = language.maximalIdentifier
        switch identifier {
        case let value where value.hasPrefix("en"):
            return "English (US)"
        case let value where value.hasPrefix("ja"):
            return "Japanese"
        case let value where value.hasPrefix("zh"):
            return "Chinese (Mandarin)"
        default:
            return identifier
        }
    }
}
