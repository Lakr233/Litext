![Hero](./Artworks/hero.png)

# Litext

A lightweight rich-text library for UIKit and AppKit platforms.

**Note: This fork is reimplemented in Swift. While we've maintained API compatibility with the original, 100% compatibility is not guaranteed.**

## Features

- ⚡️ High performance text layout and rendering
- 📎 Native view embedding via attachments
- 🔗 Clickable links support
- 🎨 Custom drawing callbacks
- 📐 Auto layout integration (experimental)
- 📃 Text Selection

![Screenshot](./Artworks/screenshot.png)

## Supported Platforms

- iOS 13.0+
- macOS 12.0+

## Installation

Add Litext as a dependency in your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/Helixform/Litext.git", branch: "main")
]
```

## Usage

```swift
import Litext

let label = LTXLabel()
view.addSubview(label)

// Create and style attributed string
let attributedString = NSMutableAttributedString(
    string: "Hello, Litext!",
    attributes: [
        .font: NSFont.systemFont(ofSize: 16),
        .foregroundColor: NSColor.labelColor
    ]
)

// Set the attributed text
label.attributedText = attributedString
```

## License

This project is licensed under the MIT License - see the [LICENSE](./LICENSE) file for details.
