//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

#if !os(watchOS)

    import CoreText
    import Foundation
    import Litext
    @testable import LitextAnimation
    import Testing

    /// Counts the lines it draws a background for.
    @MainActor
    private final class CountingRenderer: TextLabel.LineRenderer {
        var backgroundLines: [Int] = []
        var glyphLines: [Int] = []

        override func drawBackground(of _: CTLine, at index: Int, in _: CGContext, layout _: TextLabel.Layout) {
            backgroundLines.append(index)
        }

        override func drawGlyphs(of line: CTLine, at index: Int, in context: CGContext, layout: TextLabel.Layout) {
            glyphLines.append(index)
            super.drawGlyphs(of: line, at: index, in: context, layout: layout)
        }
    }

    /// Animates every change for a second and draws lines in flight as they look at rest.
    @MainActor
    private final class RestingLineAnimator: LTXTextAnimator {
        private(set) var animatingRange: NSRange?
        private var endTime: CFTimeInterval = 0
        var drawsBackgroundOnly = false

        func animateChange(_ context: LTXAnimationContext, at time: CFTimeInterval) {
            animatingRange = context.change.insertedRange
            endTime = time + 1
        }

        func advance(to time: CFTimeInterval, invalidation: LTXInvalidationContext) -> Bool {
            invalidation.invalidateAll()
            if time >= endTime {
                animatingRange = nil
            }
            return animatingRange != nil
        }

        func draw(_ line: LTXAnimatedLine, in context: CGContext, at _: CFTimeInterval) -> Bool {
            if drawsBackgroundOnly {
                line.drawBackground(in: context)
            } else {
                line.draw(in: context)
            }
            return true
        }

        func finish() {
            animatingRange = nil
        }
    }

    @Suite("Line renderer while animating")
    @MainActor
    struct LTXLineRendererTests {
        @Test
        func `an animatable label hands its renderer to its own layout`() {
            let label = makeLabel("Hello")
            let renderer = TextLabel.LineRenderer()
            label.lineRenderer = renderer
            label.attributedText = text("Hello, world")
            #expect(label.textLayout.lineRenderer === renderer)
        }

        @Test
        func `a line in flight is drawn with its renderer's background`() {
            let animator = RestingLineAnimator()
            let renderer = CountingRenderer()
            let window = makeWindow()
            let label = makeLabel("", animator: animator)
            label.lineRenderer = renderer
            addToWindow(label, window)
            label.attributedText = text("Hello")
            performLayoutPass(label)
            #expect(label.isAnimating)

            renderer.backgroundLines = []
            renderer.glyphLines = []
            let bytes = drawAnimationLayer(of: label)
            #expect(renderer.backgroundLines == [0])
            #expect(renderer.glyphLines == [0])
            #expect(inkedByteCount(bytes) > 0)
        }

        @Test
        func `an effect that draws its own glyphs can still draw the background alone`() {
            let animator = RestingLineAnimator()
            animator.drawsBackgroundOnly = true
            let renderer = CountingRenderer()
            let window = makeWindow()
            let label = makeLabel("", animator: animator)
            label.lineRenderer = renderer
            addToWindow(label, window)
            label.attributedText = text("Hello")
            performLayoutPass(label)

            renderer.backgroundLines = []
            renderer.glyphLines = []
            let bytes = drawAnimationLayer(of: label)
            #expect(renderer.backgroundLines == [0])
            #expect(renderer.glyphLines.isEmpty)
            #expect(inkedByteCount(bytes) == 0)
        }

        @Test
        func `a line in flight draws like the resting label`() {
            let animator = RestingLineAnimator()
            let window = makeWindow()
            let label = makeLabel("", animator: animator)
            addToWindow(label, window)
            label.attributedText = text("Hello")
            performLayoutPass(label)
            let animated = drawAnimationLayer(of: label)

            label.finishAnimations()
            let resting = renderedBytes(label)
            #expect(inkedByteCount(animated) > 0)
            #expect(inkedByteCount(animated) == inkedByteCount(resting))
        }

        @Test
        func `a line made without a layout draws its glyphs alone`() throws {
            let layout = TextLabel.Layout(attributedString: text("Hello"))
            layout.containerSize = CGSize(width: 200, height: 100)
            let laidOut = try #require(layout.layoutLines.first)
            let line = LTXAnimatedLine(
                line: laidOut.line,
                index: 0,
                stringRange: laidOut.stringRange,
                baselineOrigin: laidOut.baselineOrigin,
                rect: laidOut.rect,
            )
            #expect(line.lineRenderer == nil)
        }
    }

#endif
