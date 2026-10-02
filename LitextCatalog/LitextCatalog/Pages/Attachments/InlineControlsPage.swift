//
//  InlineControlsPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  Real UIKit and AppKit controls as attachments: they take their own
//  touches and clicks while the text around them stays selectable, and they
//  say what to copy through TextLabel.AttachmentRepresentable.
//

import Litext
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct InlineControlsPage: View {
    private static let code = """
    let toggle = UISwitch()                 // NSSwitch on macOS
    toggle.addAction(UIAction { _ in /* … */ }, for: .valueChanged)
    toggle.sizeToFit()

    // A container that tells copy what the control stands for.
    final class ControlBox: UIView, TextLabel.AttachmentRepresentable {
        func attributedStringRepresentation() -> NSAttributedString {
            NSAttributedString(string: "[switch]")
        }
    }

    let attachment = TextLabel.Attachment(size: toggle.bounds.size, view: box)
    // Center the control on the lowercase letters around it.
    attachment.descent = (toggle.bounds.height - font.xHeight) / 2
    text.append(attachment.attributedString(attributes: body))

    label.isSelectable = true   // the words stay selectable around the control
    """

    @State private var model = InlineControlsModel()

    var body: some View {
        CatalogPageScaffold(.inlineControls, code: Self.code) {
            PlatformViewHost.label {
                let label = TextLabelView()
                label.isSelectable = true
                return label
            } update: { label in
                label.delegate = model
                if label.attributedText !== model.text, !label.attributedText.isEqual(to: model.text) {
                    label.attributedText = model.text
                }
            }
            .accessibilityIdentifier("demo.inlineControls.label")
        } controls: {
            CatalogReadout("Button taps", value: "\(model.taps)", identifier: "state.inlineControls.taps")
            #if !os(tvOS)
                CatalogReadout("Switch", value: model.isOn ? "on" : "off", identifier: "state.inlineControls.switch")
                CatalogReadout(
                    "Slider",
                    value: model.level.formatted(.percent.precision(.fractionLength(0))),
                    identifier: "state.inlineControls.slider",
                )
            #endif
            CatalogReadout("Selected text", value: model.selectedText, identifier: "state.inlineControls.selection")
            CatalogNote(
                "Touches on an attachment's view go to the view, not to the label's selection. Select across a control and the copied text uses its AttachmentRepresentable text, such as [switch].",
            )
        }
    }
}

/// Owns the controls, keeps their state for the readouts, and builds the text once.
@Observable
private final class InlineControlsModel: NSObject, TextLabelViewDelegate {
    var taps = 0
    var isOn = true
    var level = 0.4
    var selectedText = "none"

    @ObservationIgnored private(set) var text = NSAttributedString()
    @ObservationIgnored private var progress: InlineProgress?

    override init() {
        super.init()
        text = makeText()
    }

    // MARK: Text

    private func makeText() -> NSAttributedString {
        let font = PlatformFont.systemFont(ofSize: 17)
        let body: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: PlatformColor.label,
        ]
        let text = NSMutableAttributedString()
        func append(_ string: String) {
            text.append(NSAttributedString(string: string, attributes: body))
        }
        func append(control: PlatformView, copyText: String) {
            let box = InlineControlBox(wrapping: control, copyText: copyText)
            let attachment = TextLabel.Attachment(size: box.bounds.size, view: box)
            attachment.descent = max((box.bounds.height - font.xHeight) / 2, 0)
            text.append(attachment.attributedString(attributes: body))
        }

        append("Press ")
        append(control: makeButton(), copyText: "[button]")
        append(" to count taps")
        #if os(tvOS)
            append(". Switches and sliders are not available on tvOS, but a progress bar ")
            let progress = InlineProgress(level: level)
            self.progress = progress
            append(control: progress.view, copyText: "[progress]")
            append(" still sits in the line.")
        #else
            append(", flip ")
            append(control: makeSwitch(), copyText: "[switch]")
            append(" to turn something on, and drag ")
            append(control: makeSlider(), copyText: "[slider]")
            append(" to fill the bar ")
            let progress = InlineProgress(level: level)
            self.progress = progress
            append(control: progress.view, copyText: "[progress]")
            append(". The words between the controls are ordinary text: drag across them to select, and the selection skips over nothing.")
        #endif
        return text
    }

    // MARK: Controls

    #if canImport(UIKit)
        private func makeButton() -> PlatformView {
            var configuration = UIButton.Configuration.tinted()
            configuration.title = "Tap me"
            configuration.buttonSize = .small
            configuration.cornerStyle = .capsule
            let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
                self?.taps += 1
            })
            button.sizeToFit()
            return button
        }

        #if !os(tvOS)
            private func makeSwitch() -> PlatformView {
                let toggle = UISwitch()
                toggle.isOn = isOn
                toggle.addAction(UIAction { [weak self, weak toggle] _ in
                    self?.isOn = toggle?.isOn ?? false
                }, for: .valueChanged)
                toggle.sizeToFit()
                return toggle
            }

            private func makeSlider() -> PlatformView {
                let slider = UISlider()
                slider.value = Float(level)
                slider.addAction(UIAction { [weak self, weak slider] _ in
                    guard let self, let slider else { return }
                    level = Double(slider.value)
                    progress?.setLevel(level)
                }, for: .valueChanged)
                slider.sizeToFit()
                slider.frame.size.width = 120
                return slider
            }
        #endif

    #elseif canImport(AppKit)
        private func makeButton() -> PlatformView {
            let button = NSButton(title: "Tap me", target: self, action: #selector(buttonPressed))
            button.bezelStyle = .push
            button.controlSize = .small
            button.sizeToFit()
            return button
        }

        private func makeSwitch() -> PlatformView {
            let toggle = NSSwitch()
            toggle.controlSize = .small
            toggle.state = isOn ? .on : .off
            toggle.target = self
            toggle.action = #selector(switchChanged(_:))
            toggle.sizeToFit()
            return toggle
        }

        private func makeSlider() -> PlatformView {
            let slider = NSSlider(value: level, minValue: 0, maxValue: 1, target: self, action: #selector(sliderChanged(_:)))
            slider.controlSize = .small
            slider.isContinuous = true
            slider.sizeToFit()
            slider.frame.size.width = 120
            return slider
        }

        @objc private func buttonPressed() {
            taps += 1
        }

        @objc private func switchChanged(_ sender: NSSwitch) {
            isOn = sender.state == .on
        }

        @objc private func sliderChanged(_ sender: NSSlider) {
            level = sender.doubleValue
            progress?.setLevel(level)
        }
    #endif

    // MARK: TextLabelViewDelegate

    func textLabelView(
        _: TextLabelView,
        didTapHighlightRegion _: TextLabel.HighlightRegion,
        at _: CGPoint,
    ) {}

    func textLabelView(_ label: TextLabelView, didChangeSelection _: NSRange?) {
        selectedText = label.selectedPlainText() ?? "none"
    }
}

/// Holds a control inside an attachment and says what stands for it when the
/// selection is copied.
private final class InlineControlBox: PlatformView, TextLabel.AttachmentRepresentable {
    private let copyText: String

    init(wrapping control: PlatformView, copyText: String) {
        self.copyText = copyText
        super.init(frame: CGRect(origin: .zero, size: control.frame.size))
        control.frame = bounds
        #if canImport(UIKit)
            control.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        #else
            control.autoresizingMask = [.width, .height]
        #endif
        addSubview(control)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attributedStringRepresentation() -> NSAttributedString {
        NSAttributedString(string: copyText)
    }
}

/// A determinate progress bar the slider drives.
@MainActor
private final class InlineProgress {
    #if canImport(UIKit)
        private let bar = UIProgressView(progressViewStyle: .default)
    #else
        private let bar = NSProgressIndicator()
    #endif

    var view: PlatformView {
        bar
    }

    init(level: Double) {
        #if canImport(UIKit)
            bar.frame = CGRect(x: 0, y: 0, width: 80, height: 4)
        #else
            bar.style = .bar
            bar.isIndeterminate = false
            bar.minValue = 0
            bar.maxValue = 1
            bar.controlSize = .small
            bar.frame = CGRect(x: 0, y: 0, width: 80, height: 12)
        #endif
        setLevel(level)
    }

    func setLevel(_ level: Double) {
        #if canImport(UIKit)
            bar.progress = Float(level)
        #else
            bar.doubleValue = level
        #endif
    }
}
