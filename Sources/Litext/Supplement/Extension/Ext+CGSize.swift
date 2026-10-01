//
//  Ext+CGSize.swift
//  Litext
//
//  Created by Litext Team.
//

import CoreGraphics

extension CGFloat {
    /// Whether this is a usable layout dimension: finite and not negative.
    ///
    /// Zero and `.greatestFiniteMagnitude` are valid, and both mean unconstrained:
    /// to measurement, and to layout, which breaks lines in a zero-wide container
    /// as in an unbounded one, so text that measures zero wide keeps its measured
    /// lines. `.greatestFiniteMagnitude` is the documented way to ask for an
    /// unbounded dimension. NaN, negative values and both infinities are
    /// invalid: no text can be laid out in them, and CoreText would either fit no
    /// line or produce non-finite geometry.
    var isValidLayoutDimension: Bool {
        isFinite && self >= 0
    }
}

extension CGSize {
    /// Whether both dimensions are valid layout dimensions. Litext skips layout,
    /// drawing and measurement for any other size. See
    /// `CGFloat.isValidLayoutDimension`.
    var isValidLayoutSize: Bool {
        width.isValidLayoutDimension && height.isValidLayoutDimension
    }
}
