//
//  CellReusePage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  A table of messages in reused cells. Each cell's label sets its
//  animationIdentity to the message it shows, so a cell scrolled onto
//  another message shows that text at once, while the live row keeps
//  fading in the text it streams. A dot next to a row lights up while its
//  label animates; the count at the bottom tallies animations on rows
//  other than the live one, and stays at zero.
//

import Litext
import LitextAnimation
import SwiftUI

struct CellReusePage: View {
    private static let code = """
    // In the cell's configure method: the identity first, then the text.
    cell.label.animationIdentity = message.id
    cell.label.attributedText = message.rendered
    // A new identity shows its text at once; more text for the same
    // identity animates.
    """

    var body: some View {
        #if os(tvOS)
            CatalogUnavailableView(page: .cellReuse, reason: "The animation pages need sliders and toggles, which tvOS does not have.")
        #else
            CatalogFillScaffold(.cellReuse, code: Self.code) {
                ReuseDemoView()
            }
        #endif
    }
}

#if !os(tvOS)

    struct ReuseDemoView: View {
        @State private var isAutoScrolling = CatalogLaunchOptions.current.isAutoScrolling
        @State private var strayAnimations = 0

        var body: some View {
            ReuseTable(isAutoScrolling: isAutoScrolling) { strayAnimations += 1 }
                .accessibilityIdentifier("demo.reuse.table")
                .ignoresSafeArea(edges: .bottom)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    HStack(spacing: 12) {
                        Toggle("Auto Scroll", isOn: $isAutoScrolling)
                            .fixedSize()
                        Spacer()
                        Text("Animations on reused rows: \(strayAnimations)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(strayAnimations == 0 ? Color.secondary : Color.red)
                            .accessibilityIdentifier("state.reuse.strayAnimations")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.bar)
                }
        }
    }

    // MARK: - Messages

    /// The table's content: fixed messages, and one live message that streams.
    @MainActor
    final class ReuseFeed {
        struct Message {
            let id: Int
            var text: NSAttributedString
        }

        /// The row of the live message.
        static let liveRow = 2

        private(set) var messages: [Message]
        private let script = StreamingScript.make(fontSize: 15)
        private var liveTokens = 0
        private var pauseTicks = 0

        init() {
            let samples = [
                "Reused cells show their message at once.",
                "Scroll quickly: no row replays its fade, because each label's animationIdentity is the message id.",
                "表格滚动时，复用的单元格直接显示最终文本，不会重放动画。",
                "Only the live row animates, and only the text it has just received. ✨",
                "Each label owns its animator; an animator keeps one timeline for one label.",
                "Leaving the window finishes a label's animations and releases its display link.",
                "Mixed scripts keep their direction: مرحبا بالعالم.",
                "Short one.",
            ]
            messages = (0 ..< 200).map { index in
                let body = samples[index % samples.count]
                return Message(id: index, text: Self.render("#\(index)  \(body)"))
            }
            messages[Self.liveRow].text = script.prefix(tokens: 0)
        }

        /// Streams one more token into the live message, or restarts it after a pause
        /// once it is complete. Returns whether the text changed.
        func advanceLiveMessage() -> Bool {
            if liveTokens >= script.tokenEnds.count {
                pauseTicks += 1
                guard pauseTicks > 60 else { return false }
                pauseTicks = 0
                liveTokens = 0
            } else {
                liveTokens += 1
            }
            messages[Self.liveRow].text = script.prefix(tokens: liveTokens)
            return true
        }

        static func render(_ string: String) -> NSAttributedString {
            NSAttributedString(string: string, attributes: [
                .font: PlatformFont.systemFont(ofSize: 15),
                .foregroundColor: PlatformColor.label,
            ])
        }
    }

    // MARK: - Row

    /// One message row: an activity dot and an animatable label. Shared by the UIKit and
    /// AppKit tables.
    final class MessageRowView: PlatformView {
        static let padding: CGFloat = 12
        static let trailingInset: CGFloat = 20
        static let textInset: CGFloat = 30

        let label = LTXAnimatableLabel()
        private let dot = CALayer()
        private var observation: NSKeyValueObservation?
        private(set) var messageID: Int?

        /// Called when the label starts animating, with the message it shows.
        var onAnimationStart: ((Int) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            #if canImport(AppKit) && !targetEnvironment(macCatalyst)
                wantsLayer = true
            #endif
            // Each label needs its own animator: an animator keeps one label's timeline.
            label.animator = FadeInAnimator()
            addSubview(label)
            dot.cornerRadius = 4
            dot.backgroundColor = PlatformColor.systemGreen.cgColor
            dot.opacity = 0
            hostLayer.addSublayer(dot)
            observation = label.observe(\.isAnimating, options: [.new]) { [weak self] _, change in
                let isAnimating = change.newValue ?? false
                MainActor.assumeIsolated {
                    self?.animatingDidChange(isAnimating)
                }
            }
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        private var hostLayer: CALayer {
            #if canImport(UIKit)
                layer
            #else
                layer!
            #endif
        }

        /// Shows `message`. The identity goes first, so a different message appears at
        /// once and more text for the same message animates.
        func configure(_ message: ReuseFeed.Message) {
            messageID = message.id
            label.animationIdentity = message.id
            label.attributedText = message.text
        }

        private func animatingDidChange(_ isAnimating: Bool) {
            CATransaction.begin()
            CATransaction.setAnimationDuration(isAnimating ? 0.05 : 0.4)
            dot.opacity = isAnimating ? 1 : 0
            CATransaction.commit()
            if isAnimating, let messageID {
                onAnimationStart?(messageID)
            }
        }

        static func height(of text: NSAttributedString, width: CGFloat) -> CGFloat {
            let layout = TextLabel.Layout(attributedString: text)
            let size = layout.sizeThatFits(CGSize(width: max(width - textInset - trailingInset, 1), height: .greatestFiniteMagnitude))
            return (size.height + padding * 2).rounded(.up)
        }

        #if canImport(UIKit)
            override func layoutSubviews() {
                super.layoutSubviews()
                layoutRow()
            }
        #else
            override var isFlipped: Bool {
                true
            }

            override func layout() {
                super.layout()
                layoutRow()
            }
        #endif

        private func layoutRow() {
            label.frame = CGRect(
                x: Self.textInset,
                y: Self.padding,
                width: max(bounds.width - Self.textInset - Self.trailingInset, 0),
                height: max(bounds.height - Self.padding * 2, 0),
            )
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            dot.frame = CGRect(x: 12, y: Self.padding + 6, width: 8, height: 8)
            CATransaction.commit()
        }
    }

    // MARK: - Table

    private struct ReuseTable: View {
        var isAutoScrolling: Bool
        var onStrayAnimation: () -> Void

        var body: some View {
            PlatformViewHost {
                ReuseTableView()
            } update: { view in
                view.onStrayAnimation = onStrayAnimation
                view.isAutoScrolling = isAutoScrolling
            }
        }
    }

    /// The platform table, its data source, the live stream and the auto scroll.
    final class ReuseTableView: PlatformView {
        let feed = ReuseFeed()
        var onStrayAnimation: (() -> Void)?
        var isAutoScrolling = false {
            didSet { autoScrollStep = 0 }
        }

        private var streamTimer: Timer?
        private var ticks = 0
        private var autoScrollStep = 0
        private var heightCache: [Int: CGFloat] = [:]
        private var cachedWidth: CGFloat = 0

        #if canImport(UIKit)
            private let tableView = UITableView(frame: .zero, style: .plain)
        #else
            private let scrollView = NSScrollView()
            private let tableView = NSTableView()
        #endif

        override init(frame: CGRect) {
            super.init(frame: frame)
            setUpTable()
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        // MARK: Width

        #if canImport(UIKit)
            override func layoutSubviews() {
                super.layoutSubviews()
                tableWidthMayHaveChanged()
            }
        #else
            override func layout() {
                super.layout()
                tableWidthMayHaveChanged()
            }
        #endif

        /// Measures every row again when the table's width changes. The tables ask for row
        /// heights before they have their final width, and keep those heights until told.
        private func tableWidthMayHaveChanged() {
            let width = tableView.bounds.width
            guard width > 0, width != cachedWidth else { return }
            cachedWidth = width
            heightCache.removeAll()
            noteAllHeightsChanged()
        }

        // MARK: Live stream

        #if canImport(UIKit)
            override func didMoveToWindow() {
                super.didMoveToWindow()
                updateStreaming()
            }
        #else
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                updateStreaming()
            }
        #endif

        /// Streams only while on screen, like a real chat that pauses rendering offscreen.
        private func updateStreaming() {
            streamTimer?.invalidate()
            streamTimer = nil
            guard window != nil else { return }
            streamTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.tick()
                }
            }
        }

        private func tick() {
            ticks += 1
            // About fifteen tokens a second.
            if ticks.isMultiple(of: 2), feed.advanceLiveMessage() {
                liveMessageDidChange()
            }
            // Scroll a screenful every two seconds, down and back up.
            if isAutoScrolling, ticks.isMultiple(of: 60) {
                autoScrollStep += 1
                let rows = feed.messages.count
                let cycle = autoScrollStep % 8
                let target = cycle < 4 ? min(cycle * 12 + 12, rows - 1) : max((8 - cycle) * 12 - 12, 0)
                scroll(toRow: target)
            }
        }

        private func liveMessageDidChange() {
            let row = ReuseFeed.liveRow
            let message = feed.messages[row]
            visibleRowView(at: row)?.configure(message)
            let height = MessageRowView.height(of: message.text, width: cachedWidth)
            guard heightCache[message.id] != height else { return }
            heightCache[message.id] = height
            noteHeightChanged(ofRow: row)
        }

        private func height(ofRow row: Int, width: CGFloat) -> CGFloat {
            if width != cachedWidth {
                cachedWidth = width
                heightCache.removeAll()
            }
            let message = feed.messages[row]
            if let height = heightCache[message.id] {
                return height
            }
            let height = MessageRowView.height(of: message.text, width: width)
            heightCache[message.id] = height
            return height
        }

        private func rowViewDidStartAnimating(_ messageID: Int) {
            if messageID != feed.messages[ReuseFeed.liveRow].id {
                onStrayAnimation?()
            }
        }

        private func makeRowView() -> MessageRowView {
            let view = MessageRowView()
            view.onAnimationStart = { [weak self] id in
                self?.rowViewDidStartAnimating(id)
            }
            return view
        }

        // MARK: Platform tables

        #if canImport(UIKit)
            private final class Cell: UITableViewCell {
                var rowView: MessageRowView?
            }

            private func setUpTable() {
                tableView.dataSource = self
                tableView.delegate = self
                tableView.register(Cell.self, forCellReuseIdentifier: "message")
                tableView.separatorInset = UIEdgeInsets(
                    top: 0,
                    left: MessageRowView.textInset,
                    bottom: 0,
                    right: MessageRowView.trailingInset,
                )
                tableView.frame = bounds
                tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                addSubview(tableView)
            }

            private func visibleRowView(at row: Int) -> MessageRowView? {
                (tableView.cellForRow(at: IndexPath(row: row, section: 0)) as? Cell)?.rowView
            }

            private func noteHeightChanged(ofRow _: Int) {
                UIView.performWithoutAnimation {
                    tableView.performBatchUpdates(nil)
                }
            }

            private func scroll(toRow row: Int) {
                tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: .top, animated: true)
            }

            private func noteAllHeightsChanged() {
                UIView.performWithoutAnimation {
                    tableView.performBatchUpdates(nil)
                }
            }
        #else
            private func setUpTable() {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("message"))
                column.resizingMask = .autoresizingMask
                tableView.addTableColumn(column)
                tableView.headerView = nil
                tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
                tableView.style = .plain
                tableView.dataSource = self
                tableView.delegate = self
                scrollView.documentView = tableView
                scrollView.hasVerticalScroller = true
                scrollView.frame = bounds
                scrollView.autoresizingMask = [.width, .height]
                addSubview(scrollView)
            }

            private func visibleRowView(at row: Int) -> MessageRowView? {
                tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? MessageRowView
            }

            private func noteHeightChanged(ofRow row: Int) {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
                }
            }

            private func scroll(toRow row: Int) {
                tableView.scrollRowToVisible(row)
            }

            private func noteAllHeightsChanged() {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0 ..< feed.messages.count))
                }
            }
        #endif
    }

    #if canImport(UIKit)
        extension ReuseTableView: UITableViewDataSource, UITableViewDelegate {
            func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
                feed.messages.count
            }

            func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
                let cell = tableView.dequeueReusableCell(withIdentifier: "message", for: indexPath) as! Cell
                let rowView = cell.rowView ?? {
                    let view = makeRowView()
                    view.frame = cell.contentView.bounds
                    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    cell.contentView.addSubview(view)
                    cell.rowView = view
                    return view
                }()
                rowView.configure(feed.messages[indexPath.row])
                return cell
            }

            func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
                height(ofRow: indexPath.row, width: tableView.bounds.width)
            }
        }
    #else
        extension ReuseTableView: NSTableViewDataSource, NSTableViewDelegate {
            func numberOfRows(in _: NSTableView) -> Int {
                feed.messages.count
            }

            func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
                let identifier = NSUserInterfaceItemIdentifier("message")
                let rowView = tableView.makeView(withIdentifier: identifier, owner: nil) as? MessageRowView ?? {
                    let view = makeRowView()
                    view.identifier = identifier
                    return view
                }()
                rowView.configure(feed.messages[row])
                return rowView
            }

            func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
                height(ofRow: row, width: tableView.bounds.width)
            }
        }
    #endif

#endif
