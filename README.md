![Hero](./Artworks/hero.png)

# Litext

A tiny rich-text supporting library for iOS.

## Features

- High performance text layout and rendering.
- Attachments embedding with native view supports.
- Clickable links supports.
- Custom draw callbacks.
- Auto layout integration (experimental).

![Screenshot](./Artworks/screenshot.png)

## Supported Platforms

- macOS (11.0+)
- iOS (13.0+)

## Getting Started

Add Litext as a dependency in your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/Helixform/Litext.git", branch: "main")
]
```

### Basic Usage

```swift
import Litext

let label = LTXLabel()
view.addSubview(label)

// Create attributed string with styling.
let attributedString = NSMutableAttributedString(
    string: "Hello, Litext!",
    attributes: [
        .font: NSFont.systemFont(ofSize: 16),
        .foregroundColor: NSColor.labelColor
    ]
)

// Set the attributed text to display.
label.attributedText = attributedString
```

### Handling Link Actions

```swift
let linkString = NSAttributedString(
    string: "Visit our website",
    attributes: [
        .font: NSFont.systemFont(ofSize: 14),
        .link: URL(string: "https://example.com")!,
        .foregroundColor: NSColor.linkColor
    ]
)
attributedString.append(linkString)

// Handle link taps.
label.tapHandler = { highlightRegion in
    if let url = highlightRegion.attributes[.link] as? URL {
        NSWorkspace.shared.open(url)
    }
}
```

### Adding Native Views

```swift
// Create and configure attachment.
let attachment = LTXAttachment()
let switchView = NSSwitch()
attachment.view = switchView
attachment.size = switchView.intrinsicContentSize

// Add attachment to text.
//
// `kCTRunDelegateAttributeName` must be included to ensure the
// attachment is rendered correctly.
attributedString.append(
    NSAttributedString(
        string: LTXReplacementText,
        attributes: [
            .LTXAttachmentAttributeName: attachment,
            kCTRunDelegateAttributeName as NSAttributedString.Key: attachment.runDelegate
        ]
    )
)
```

## License

Licensed under MIT License, see [LICENSE](./LICENSE) for more information.
