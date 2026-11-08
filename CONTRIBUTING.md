# Contributing to WinV Clipboard

Thank you for your interest in contributing to **WinV Clipboard**! We welcome bug reports, feature suggestions, documentation enhancements, and code contributions from the community.

---

## Code of Conduct

Please be respectful, constructive, and considerate in all interactions within this project's issues, discussions, and pull requests.

---

## How Can I Contribute?

### 1. Reporting Bugs
Before opening a new issue, please check existing issues to avoid duplicates. When filing a bug report, include:
* Your macOS version (e.g., macOS 14.5 Sonoma, macOS 15.0 Sequoia).
* Steps to reproduce the behavior.
* Expected behavior vs. actual behavior.
* Relevant console logs or crash traces (if available).

### 2. Requesting Features
If you have an idea to make WinV Clipboard better:
* Open an issue labeled `enhancement`.
* Describe the use case and how the proposed feature fits into the native macOS / Windows 11 clipboard paradigm.

### 3. Submitting Pull Requests
1. Fork the repository and create your feature branch:
   ```bash
   git checkout -b feature/my-cool-feature
   ```
2. Make your changes adhering to project coding guidelines.
3. Validate that the full test suite passes:
   ```bash
   swift test
   ```
4. Verify that the application bundle compiles and signs cleanly:
   ```bash
   ./Scripts/build_app.sh
   ```
5. Commit your changes with clear, descriptive commit messages.
6. Push to your fork and submit a Pull Request against the `main` branch.

---

## Development Setup

### Prerequisites
* **Operating System**: macOS 14.0 (Sonoma) or newer.
* **Toolchain**: Xcode 15+ or Swift 5.10+ command-line tools.

### Building & Testing
You can build and test directly from the command line:

```bash
# Clone the repository
git clone https://github.com/anujawitharana/clipbaord-for-mac.git
cd clipbaord-for-mac

# Run automated tests
swift test

# Build debug executable
swift build

# Build and package release .app bundle
./Scripts/build_app.sh
```

---

## Coding Guidelines

* **Platform Conventions**: Maintain native macOS look and feel using standard AppKit and SwiftUI APIs.
* **Concurrency**: Ensure UI updates remain strictly on `@MainActor`. Heavy I/O, database queries, and image decoding must remain off the main thread.
* **Memory Safety**: When interfacing with SQLite C APIs, ensure text bindings use `SQLITE_TRANSIENT`.
* **Privacy by Design**: Never log sensitive clipboard contents. Preserve exclusions for password managers and concealed types.

---

## License

By contributing to WinV Clipboard, you agree that your contributions will be licensed under the project's [MIT License](LICENSE).
