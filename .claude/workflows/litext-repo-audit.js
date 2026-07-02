export const meta = {
  name: 'litext-repo-audit',
  description: 'Seven-lens parallel audit of the entire Litext repo, triaged and independently verified per change',
  phases: [
    { title: 'Analyze', detail: '7 lens-analysts read the repo in parallel' },
    { title: 'Triage', detail: 'cluster + dedup raw findings into a canonical change list' },
    { title: 'Verify', detail: 'independently verify each change → apply/care/defer/reject' },
  ],
}

// ---- Shared grounding injected into every agent -------------------------------
const CONTEXT = `PROJECT: Litext — a lightweight, high-performance rich-text library for ALL Apple platforms
(UIKit, AppKit, SwiftUI incl. watchOS). Reimplemented in Swift 6.0 with strict concurrency.

HARD, OWNER-MANDATED CONSTRAINTS (a "fix" that violates these is WRONG — flag as reject-worthy):
1. PURE CORETEXT. 100% CTFramesetter/CTFrame/CTLine/CTRun. NO TextKit at all — never introduce
   TextKit 2 (NSTextLayoutManager/NSTextContentManager) nor TextKit 1 (NSLayoutManager) nor
   UITextView/NSTextView. Stay on the CoreText fast path.
2. COORDINATES. CG/CoreText/AppKit-native are bottom-left (+y up); UIKit is top-left (+y down).
   Litext unifies via NSView.isFlipped=true plus convertPointForTextLayout /
   convertRectFromTextLayout (bounds.height - y) bridges and a draw(in:) context flip. EVERY
   geometric change must be correct on BOTH iOS (native top-left) AND macOS (flipped) — watch for
   double-flip or missing-flip bugs.
3. Swift 6 language mode, full data-race safety, @MainActor. Must compile on all 6 platforms
   incl. watchOS, where UIView/UIColor/UIBezierPath/UIApplication are UNAVAILABLE and LTXLabel is
   entirely behind #if !os(watchOS). Only LitextLabel (SwiftUI) works on watchOS.

REPO LAYOUT (paths relative to repo root):
- Sources/Litext/**            the library (primary audit surface, ~3467 LOC, 32 files)
- Tests/LitextTests/**         SwiftPM unit tests
- LitextSamples/**             sample apps (UIKit/SwiftUI/watchOS) + xcodeproj unit/UI tests
- Script/**, .github/**        build/test/perf scripts and CI
- Package.swift, .swiftlint.yml, .swiftformat   config`

const INVENTORY = `SOURCE FILE INVENTORY (LOC  path):
   17  Sources/Litext/Litext.swift
   67  Sources/Litext/LTXLabel/Attachments/LTXAttachment.swift
   52  Sources/Litext/LTXLabel/Attachments/LTXLabel+Attachment.swift
   19  Sources/Litext/LTXLabel/DrawAction/LTXLineDrawingAction.swift
   25  Sources/Litext/LTXLabel/Extension/Ext+UIView.swift
   54  Sources/Litext/LTXLabel/Highlight/LTXHighlightRegion.swift
   91  Sources/Litext/LTXLabel/Highlight/LTXLabel+HighlightRegion.swift
   59  Sources/Litext/LTXLabel/Interaction/LTXLabel+Interaction.swift
  285  Sources/Litext/LTXLabel/Interaction/LTXLabel+Interaction@AppKit.swift
   34  Sources/Litext/LTXLabel/Interaction/LTXLabel+LTXSelectionHandleDelegate.swift
  415  Sources/Litext/LTXLabel/Interaction/LTXLabel+Touches.swift
   45  Sources/Litext/LTXLabel/Interaction/LTXLabel+UIContextMenuInteractionDelegate.swift
   21  Sources/Litext/LTXLabel/Interaction/LTXLabel+UIPointerInteractionDelegate.swift
  225  Sources/Litext/LTXLabel/LTXLabel.swift
   32  Sources/Litext/LTXLabel/LTXLabel+Delegate.swift
   55  Sources/Litext/LTXLabel/Menu/LTXLabelMenuItem.swift
   11  Sources/Litext/LTXLabel/Selection/LTXAttributeStringRepresentable.swift
   53  Sources/Litext/LTXLabel/Selection/LTXLabel+Select.swift
  101  Sources/Litext/LTXLabel/Selection/LTXLabel+Selection.swift
  134  Sources/Litext/LTXLabel/Selection/LTXLabel+SelectionLayer.swift
  135  Sources/Litext/LTXLabel/Selection/LTXSelectionHandle.swift
   38  Sources/Litext/LTXLabel/TextLayout/LTXLabel+Draw.swift
  108  Sources/Litext/LTXLabel/TextLayout/LTXLabel+Layout.swift
  128  Sources/Litext/LTXLabel/TextLayout/LTXLabel+Rect.swift
  559  Sources/Litext/LTXLabel/TextLayout/LTXTextLayout.swift
   44  Sources/Litext/Supplement/Extension/Ext+NSBezierPath.swift
   28  Sources/Litext/Supplement/Extension/Ext+NSRange.swift
   38  Sources/Litext/Supplement/Extension/Ext+NSString.swift
   23  Sources/Litext/Supplement/LocalizedText.swift
   23  Sources/Litext/Supplement/LTXPlatformHelpers.swift
   30  Sources/Litext/Supplement/LTXPlatformTypes.swift
  518  Sources/Litext/SwiftUI/LitextLabel.swift`

// ---- The 7 lenses -------------------------------------------------------------
const LENSES = [
  { key: 'correctness', title: 'Correctness (logic & bugs)', focus:
`Hunt real defects: off-by-one and range math (NSRange/CFRange, UTF-16 vs character indices),
nil/optional mishandling, force-unwraps that can trap, incorrect comparisons, integer/float edge
cases, empty-string / empty-attributed-string / zero-size bounds, reentrancy, retain cycles
(closures capturing self/label strongly), lifecycle bugs (deinit, weak/unowned), concurrency
(@MainActor violations, Sendable, data races), and any geometry that double-flips or misses a flip
between iOS top-left and macOS flipped coordinates.` },
  { key: 'state-machine', title: 'State-machine integrity', focus:
`Audit interaction/selection/touch/gesture/pointer state. Map the implicit state machines in
LTXLabel+Touches, LTXLabel+Select/Selection/SelectionLayer, LTXSelectionHandle, the AppKit
interaction file, and SwiftUI LitextLabel. Look for: unreachable/invalid states, transitions that
forget to reset state, dangling drag/selection state after cancel, missing cleanup when
attributedText changes, handle state desync, and event ordering assumptions that can break.` },
  { key: 'ssot', title: 'Single-source-of-truth / duplication', focus:
`Find duplicated logic and divergent parallel implementations: copy-pasted coordinate conversions,
repeated CoreText line/run iteration, parallel UIKit vs AppKit branches that should share a helper,
repeated magic constants, the same rect/point math inlined in several places. Propose extracting a
single canonical helper. Be concrete about which call sites collapse together.` },
  { key: 'api-design', title: 'API design / abstraction / subclassing', focus:
`Evaluate the public surface and extension points: access control (public vs internal correctness),
naming consistency, delegate/callback design, how LTXLabel is meant to be subclassed/composed,
open vs final, value vs reference choices, default-argument ergonomics, and whether
abstractions leak platform details. Flag over- or under-abstraction. Respect: no migration to
TextKit-style APIs.` },
  { key: 'performance', title: 'Performance', focus:
`Focus on hot paths: draw(in:)/LTXLabel+Draw, layout/LTXTextLayout framesetting, LTXLabel+Rect/
Layout, selection-rect computation, touch hit-testing. Look for redundant CTFramesetter/CTFrame
creation, per-frame allocations, O(n^2) line/run scans, missing caches/invalidation, repeated
attributed-string copies, layout recomputation that could be memoized. Each finding must name the
path and why it is hot. Do NOT propose leaving the CoreText fast path.` },
  { key: 'clarity', title: 'Clarity / readability / dead code', focus:
`Improve maintainability: dead/unused code, unreachable branches, misleading or stale comments,
magic numbers that want named constants, over-long functions that should be decomposed, confusing
names, inconsistent style vs the surrounding code, and TODO/FIXME debt. Keep suggestions in the
idiom of the existing code.` },
  { key: 'coretext-api', title: 'CoreText framework correctness', focus:
`Verify correct CoreText usage: CTFramesetter/CTFramesetterCreateFrame, CTFrameGetLines/
CTFrameGetLineOrigins, CTLineGetTypographicBounds/CTLineGetOffsetForStringIndex/
CTLineGetStringIndexForPosition, CTRun attributes, CTFrameGetVisibleStringRange, path/rect setup,
and CoreFoundation memory rules (create/copy ownership, no over-release under ARC bridging, correct
toll-free bridging). Confirm the right CoreText API is used for each job and that NO TextKit has
crept in. Geometry must be coordinate-correct on both platforms.` },
]

// ---- Schemas ------------------------------------------------------------------
const FINDINGS_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['title', 'location', 'severity', 'problem', 'proposedChange', 'rationale'],
        properties: {
          title: { type: 'string', description: 'short imperative title of the change' },
          location: { type: 'string', description: 'file:line (or file:startLine-endLine) of the relevant code' },
          severity: { type: 'string', enum: ['high', 'medium', 'low'] },
          problem: { type: 'string', description: 'what is wrong / suboptimal, grounded in the actual code' },
          proposedChange: { type: 'string', description: 'the concrete change to make' },
          rationale: { type: 'string', description: 'why it is better, and any cross-platform/constraint considerations' },
        },
      },
    },
  },
}

const TRIAGE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['changes'],
  properties: {
    changes: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['id', 'title', 'lenses', 'location', 'severity', 'problem', 'proposedChange'],
        properties: {
          id: { type: 'string', description: 'stable id like C1, C2, ...' },
          title: { type: 'string' },
          lenses: { type: 'array', items: { type: 'string' }, description: 'which lenses raised this (merged)' },
          location: { type: 'string', description: 'canonical file:line(s); list all affected sites' },
          severity: { type: 'string', enum: ['high', 'medium', 'low'] },
          problem: { type: 'string' },
          proposedChange: { type: 'string' },
          mergedFrom: { type: 'array', items: { type: 'string' }, description: 'titles of raw findings folded in' },
        },
      },
    },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['id', 'verdict', 'confidence', 'isReal', 'reasoning', 'evidence', 'crossPlatform'],
  properties: {
    id: { type: 'string' },
    verdict: { type: 'string', enum: ['apply', 'care', 'defer', 'reject'],
      description: 'apply=real, low-risk, do now; care=worthwhile but needs careful impl/behavioral risk; defer=legit but low-priority/large/out-of-scope; reject=not a real issue, wrong, or violates a hard constraint' },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
    isReal: { type: 'boolean', description: 'after independently re-reading the code, is the problem genuinely real?' },
    reasoning: { type: 'string', description: 'independent logical-integrity reasoning from re-reading the actual code' },
    evidence: { type: 'string', description: 'concrete evidence: quoted code, Apple SDK/doc facts, gh code-search refs if used' },
    crossPlatform: { type: 'string', description: 'does it hold on iOS (top-left), macOS (flipped), and watchOS? any double-flip/availability risk?' },
  },
}

// ---- Prompt builders ----------------------------------------------------------
function analystPrompt(l) {
  return `${CONTEXT}

${INVENTORY}

YOU ARE THE "${l.title}" ANALYST. Examine the ENTIRE repo through ONLY this lens:
${l.focus}

INSTRUCTIONS:
- Read the actual code. Use Read on the files above (start with the largest/most relevant to your
  lens) and Grep to trace patterns across files. Primary surface is Sources/Litext/**, but you may
  also flag issues in Tests/, LitextSamples/, Script/, .github/, or config files when they fall
  squarely in your lens.
- Report ONLY through your lens — do not duplicate other lenses' territory.
- Every finding MUST cite a real file:line you actually read, describe the problem grounded in the
  real code (quote the relevant snippet in 'problem'), and propose a concrete change.
- Prefer a focused set of high-signal findings over a long shallow list. Skip nits that are pure
  style already enforced by swiftformat/swiftlint.
- Do NOT propose anything that violates the hard constraints (no TextKit, keep coordinate bridges,
  keep watchOS #if guards, keep Swift 6 concurrency).

Return findings via the structured output tool.`
}

function triagePrompt(findings) {
  return `${CONTEXT}

You are the TRIAGE step. Below are ${findings.length} raw findings from 7 parallel lens-analysts.
Cluster and deduplicate them into a CANONICAL change list.

RULES:
- Merge findings that describe the same underlying change (even if worded differently or found by
  different lenses) into ONE canonical change. Record every lens that raised it in 'lenses' and the
  original titles in 'mergedFrom'. Union all affected sites into 'location'.
- Keep distinct problems separate even if they touch the same file.
- Assign stable ids C1, C2, C3, ... ordered by severity then by breadth (how many lenses agreed).
- Preserve the strongest severity among merged items.
- Do NOT invent new findings and do NOT drop any real finding; if something is pure noise/style,
  you may fold it but note it.

RAW FINDINGS (JSON):
${JSON.stringify(findings, null, 1)}

Return the canonical change list via the structured output tool.`
}

function verifyPrompt(c) {
  return `${CONTEXT}

You are an INDEPENDENT VERIFIER. Do NOT trust the finding below — re-derive everything yourself.

CANDIDATE CHANGE ${c.id}: ${c.title}
Raised by lenses: ${(c.lenses || []).join(', ')}
Claimed location(s): ${c.location}
Severity (claimed): ${c.severity}
Problem (claimed): ${c.problem}
Proposed change: ${c.proposedChange}

VERIFY independently:
1. LOGICAL INTEGRITY — Read the cited file(s) and surrounding context yourself. Is the problem
   genuinely real, or did the analyst misread? Quote the real code in your evidence.
2. APPLE SDK / DOCS — When the change hinges on framework behavior (CoreText, CoreFoundation memory
   rules, UIKit/AppKit APIs, availability), confirm against Apple SDK headers and developer.apple.com
   docs. Use WebSearch/WebFetch for developer.apple.com when needed.
3. CODE REFERENCES — Only if the change depends on an external/upstream API convention, you MAY use
   "gh search code ..." via Bash to check how it is used elsewhere. NOTE: gh search code is
   rate-limited to ~10/hour across this whole run — use it sparingly or not at all; prefer local
   Read/Grep and Apple docs.
4. CROSS-PLATFORM FIT — Confirm the change is correct on iOS (native top-left), macOS (flipped via
   isFlipped + convert bridges, draw(in:) flip) with no double-flip, AND that it still compiles on
   watchOS (LTXLabel is #if !os(watchOS); UIView/UIColor/UIBezierPath/UIApplication unavailable).
   Confirm it stays on the pure-CoreText fast path and keeps Swift 6 concurrency correctness.

Then assign a verdict: apply / care / defer / reject (see schema). Be skeptical: default toward
reject or defer when the problem is not clearly real, and toward "care" when real but risky.

Return your verdict via the structured output tool.`
}

// ---- Phase 1: Analyze (7 lenses in parallel) ---------------------------------
phase('Analyze')
const analystResults = await parallel(LENSES.map((l) => () =>
  agent(analystPrompt(l), { label: `analyze:${l.key}`, phase: 'Analyze', schema: FINDINGS_SCHEMA })
))
const allFindings = analystResults.flatMap((r, i) =>
  (r && r.findings ? r.findings : []).map((f) => ({ ...f, lens: LENSES[i].key }))
)
const lensesOk = analystResults.filter(Boolean).length
log(`Analyze complete: ${allFindings.length} raw findings from ${lensesOk}/7 lenses`)

if (allFindings.length === 0) {
  return { changes: [], verdicts: [], note: 'No findings produced by any lens.' }
}

// ---- Phase 2: Triage (barrier — needs ALL findings to dedup) -----------------
phase('Triage')
const triage = await agent(triagePrompt(allFindings), { label: 'triage', phase: 'Triage', schema: TRIAGE_SCHEMA })
const changes = (triage && triage.changes) ? triage.changes : []
log(`Triage complete: ${changes.length} canonical changes after cluster+dedup`)

// ---- Phase 3: Verify (per-change, parallel) ----------------------------------
phase('Verify')
const verdicts = await parallel(changes.map((c) => () =>
  agent(verifyPrompt(c), { label: `verify:${c.id}`, phase: 'Verify', schema: VERDICT_SCHEMA })
    .then((v) => ({ ...c, verdict: v || null }))
))

const verified = verdicts.filter(Boolean)
const counts = verified.reduce((acc, v) => {
  const k = v.verdict ? v.verdict.verdict : 'unknown'
  acc[k] = (acc[k] || 0) + 1
  return acc
}, {})
log(`Verify complete: ${JSON.stringify(counts)}`)

return {
  rawFindingCount: allFindings.length,
  lensesOk,
  canonicalChanges: changes,
  verified,
  verdictCounts: counts,
}
