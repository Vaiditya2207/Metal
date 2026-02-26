# Metal

**Metal** is a high-performance, macOS-native web browser and engine built exclusively for Apple Silicon with the **Zig** programming language.

## Overview

Metal is designed to be a modern, lightweight, and deeply integrated browser for macOS. Unlike many modern browsers that rely on Chromium or WebKit, Metal features a custom rendering engine built from the ground up using the Apple Metal API for GPU acceleration.

### Key Features

- **Custom Engine**: A complete HTML/CSS parsing and layout engine built in Zig.
- **GPU Accelerated**: Rendering pipeline utilizes Apple's Metal API for 120Hz ProMotion performance.
- **Privacy First**: On-device ML for predictive features without data exfiltration.
- **Developer Centric**: Native developer tools with advanced profiling and debugging.
- **Efficiency**: Targeted RSS of < 30MB for an idle tab, leveraging macOS Unified Memory Architecture.

## Project Structure

- `src/`: Core browser and engine source code (Zig).
- `docs/`: Technical specifications (SRS) and design documents.
- `resources/`: Assets and UI resources.
- `tests/`: Unit and integration tests.

## Prerequisites

- **macOS 14+** (Sonoma or later)
- **Apple Silicon** (M1, M2, M3, etc.)
- **Zig 0.14.0+**

## Getting Started

To build and run Metal locally:

```bash
zig build run
```

To run tests:

```bash
zig build test
```

## Status

Metal is currently in the **Draft/Phase 0** stage. See the [SRS](docs/raw/srs.txt) for detailed requirements and the roadmap.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
