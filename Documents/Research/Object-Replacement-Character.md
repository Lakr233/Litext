# Object replacement characters on iOS 17

Why the first line of a list item sat further right than the lines it wrapped onto on iOS 17, and what was measured to fix it. The fonts were read from iOS 16.6.1, 17.6.1 and 18.0 restore images; the layouts ran on an iOS 27 simulator and an Apple silicon Mac.

## The symptom

MarkdownView opens each list item with an object replacement character (U+FFFC) that carries a `LineDrawingAction` for the bullet and a `.litextAttachment` for copying, but no run delegate. On iOS 17 the item's first line started about 0.6 em to the right of its wrapped lines, as if a narrow space came after the bullet. iOS 18 and later never showed it.

## The cause

Without a run delegate, CoreText typesets the character with its font like any other. Whether that font has a glyph for it decides what happens:

| Font | U+FFFC |
| --- | --- |
| System font, iOS 16.6.1 | no glyph |
| System font, iOS 17.6.1 | no glyph |
| System font, iOS 18.0 | `.null`, no advance |
| System font, macOS 27 | `.null`, no advance |
| PingFang SC, Helvetica | no glyph |
| Menlo, Courier New | a glyph 0.6 em wide |
| Arial, Times New Roman | a glyph 1 em wide |
| Apple Symbols | a glyph with no advance |

When the font has no glyph, CoreText borrows one from another font. Typesetting the character in PingFang SC, or in the iOS 17 system font, on iOS 27 borrowed Menlo's. That glyph draws nothing but is 0.6 em wide: 10.23 points at 17 points. The rest of the first line moved over by that much, and the run's font, which MarkdownView reads to place the bullet, became Menlo.

The same text in the iOS 27 system font put the character in the system font at no width. So the bug follows the font, not the system version. A theme whose body font lacks the glyph shows it on iOS 18 and later too.

iOS 16 has the same font as iOS 17 here. Whether it showed the gap depends on which font iOS 16's CoreText borrows the glyph from, which could not be checked without an iOS 16 runtime.

## The fix

`TextLabel.Layout` typesets a copy of its string, `typesetString`, in which every replacement character without a run delegate gets one, unless its font already maps the character to a glyph with no advance:

- The delegate reports no width and the font's ascent and descent. The line keeps the height the font gives it, and CoreText no longer borrows a glyph, so the run keeps its own font.
- Where the font already maps the character to a glyph with no advance, as the current system fonts do, the string is left alone. Lines laid out in the system font on iOS 27 are bit-identical before and after the fix.
- `attributedString` stays the string the layout was given.
- One delegate is shared per pair of metrics. CoreText compares run delegates by identity, so a delegate per string would make each streamed string differ from the last at its first replacement character, and `reuseTypesetting(from:)` would typeset the document again from there.
- A string with no font typesets in Helvetica at 12 points, CoreText's default, which has no glyph either, so it gets a delegate for that font.

Measured on the iOS 27 simulator with MarkdownView's default theme, at 17 points:

| Body font | Before | After |
| --- | --- | --- |
| iOS 17.6.1 system font | first line 10.23 pt right of the next, marker in Menlo | 0 pt, marker in the body font |
| PingFang SC | 10.23 pt, Menlo | 0 pt, PingFang SC |
| iOS 27 system font | 0 pt | 0 pt, same layout |

`LitextReplacementCharacterTests` holds the width, the line height, the run's font, the drawing, the untouched string and line reuse. Six of its tests fail without the fix.
