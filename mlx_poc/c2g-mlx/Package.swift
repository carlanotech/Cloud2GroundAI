// swift-tools-version: 5.9
//
// c2g-mlx — minimal local-inference CLI for the Cloud2Ground bridge.
// Depends on mlx-swift-lm (the 3.x line, where MLXLLM / MLXLMCommon now live)
// plus Hugging Face downloader + tokenizer integration packages.
//
// If versions drift and this stops resolving, the canonical working reference
// is Tools/llm-tool in https://github.com/ml-explore/mlx-swift-examples —
// copy its Package.swift dependency pins.

import PackageDescription

let package = Package(
    name: "c2g-mlx",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMajor(from: "3.31.3")),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "c2g-mlx",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ]
        )
    ]
)
