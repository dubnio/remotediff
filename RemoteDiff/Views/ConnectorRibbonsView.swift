import SwiftUI

// MARK: - Connector Ribbons View

/// Draws cubic Bézier connector ribbons between the two **unaligned** panes
/// of a side-by-side diff. For each `ConnectorLink`, the ribbon's left edge
/// occupies the old-file line range and the right edge occupies the new-file
/// line range. Because the two files have different line counts and different
/// Y positions for "the same" change, the ribbons swoop diagonally — narrow
/// on the side that has fewer lines, wide on the side that has more.
///
/// Pure additions collapse to a point on the left edge (a wedge that opens
/// to the right). Pure deletions are the mirror image.
struct ConnectorRibbonsView: View {
    let links: [ConnectorLink]
    let lineHeight: CGFloat
    let theme: SyntaxTheme
    let width: CGFloat
    /// Total height of the canvas — should match the taller pane so the ribbons
    /// scroll in lock-step with the code panes inside the shared `ScrollView`.
    let totalHeight: CGFloat
    /// Vertical inset from the top of this view to line 1's Y origin.
    /// Defaults to 2 to match `CodePaneView`'s `textContainerInset.height`.
    var topInset: CGFloat = 2

    var body: some View {
        Canvas { context, _ in
            for link in links {
                draw(link: link, in: &context)
            }
        }
        .frame(width: width, height: totalHeight)
        .allowsHitTesting(false)
    }

    // MARK: - Drawing

    private func draw(link: ConnectorLink, in context: inout GraphicsContext) {
        // 1-based line numbers → Y in canvas coordinates.
        let oldYTop = topInset + CGFloat(link.oldStartLine - 1) * lineHeight
        let oldYBot = topInset + CGFloat(link.oldEndLine   - 1) * lineHeight
        let newYTop = topInset + CGFloat(link.newStartLine - 1) * lineHeight
        let newYBot = topInset + CGFloat(link.newEndLine   - 1) * lineHeight

        let fillPath = ribbonPath(
            oldYTop: oldYTop, oldYBot: oldYBot,
            newYTop: newYTop, newYBot: newYBot
        )
        let edgeStrokes = edgePath(
            oldYTop: oldYTop, oldYBot: oldYBot,
            newYTop: newYTop, newYBot: newYBot
        )

        let (fill, stroke) = colors(for: link.kind)
        context.fill(fillPath, with: .color(fill))
        context.stroke(edgeStrokes, with: .color(stroke), lineWidth: 1.5)
    }

    /// Closed path for the ribbon body.
    /// Top edge:    (0, oldYTop) ⇒ cubic bezier ⇒ (width, newYTop)
    /// Right edge:  (width, newYTop) ⇒ line ⇒ (width, newYBot)
    /// Bottom edge: (width, newYBot) ⇒ cubic bezier ⇒ (0, oldYBot)
    /// Left edge:   auto-closed back to (0, oldYTop)
    ///
    /// Control points are placed at horizontal mid-width to produce a smooth
    /// "S-curve" between the two Y positions on each side.
    private func ribbonPath(
        oldYTop: CGFloat, oldYBot: CGFloat,
        newYTop: CGFloat, newYBot: CGFloat
    ) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: oldYTop))
            p.addCurve(
                to: CGPoint(x: width, y: newYTop),
                control1: CGPoint(x: width * 0.5, y: oldYTop),
                control2: CGPoint(x: width * 0.5, y: newYTop)
            )
            p.addLine(to: CGPoint(x: width, y: newYBot))
            p.addCurve(
                to: CGPoint(x: 0, y: oldYBot),
                control1: CGPoint(x: width * 0.5, y: newYBot),
                control2: CGPoint(x: width * 0.5, y: oldYBot)
            )
            p.closeSubpath()
        }
    }

    /// The two curved edges only — used for a stroke that defines the ribbon
    /// outline crisply without drawing the (often very steep) side edges.
    private func edgePath(
        oldYTop: CGFloat, oldYBot: CGFloat,
        newYTop: CGFloat, newYBot: CGFloat
    ) -> Path {
        Path { p in
            // Top edge
            p.move(to: CGPoint(x: 0, y: oldYTop))
            p.addCurve(
                to: CGPoint(x: width, y: newYTop),
                control1: CGPoint(x: width * 0.5, y: oldYTop),
                control2: CGPoint(x: width * 0.5, y: newYTop)
            )
            // Bottom edge (drawn left-to-right so control points are intuitive)
            p.move(to: CGPoint(x: 0, y: oldYBot))
            p.addCurve(
                to: CGPoint(x: width, y: newYBot),
                control1: CGPoint(x: width * 0.5, y: oldYBot),
                control2: CGPoint(x: width * 0.5, y: newYBot)
            )
        }
    }

    // MARK: - Colors

    private func colors(for kind: ConnectorLink.Kind) -> (fill: Color, stroke: Color) {
        switch kind {
        case .addition:
            return (
                ribbonColor(theme.inlineAdditionBackground, opacity: 0.32),
                ribbonColor(theme.inlineAdditionBackground, opacity: 0.95)
            )
        case .deletion:
            return (
                ribbonColor(theme.inlineDeletionBackground, opacity: 0.32),
                ribbonColor(theme.inlineDeletionBackground, opacity: 0.95)
            )
        case .modification:
            // Modifications use the theme's blue "modification" color so they
            // visually match the row backgrounds on the lines they connect.
            return (
                ribbonColor(theme.inlineModificationBackground, opacity: 0.32),
                ribbonColor(theme.inlineModificationBackground, opacity: 0.95)
            )
        }
    }

    /// Builds a SwiftUI `Color` from a `HexColor`'s RGB only, applying the given
    /// opacity directly. We deliberately ignore `hex.alpha` because some themes
    /// bake low alpha (e.g. `0x26` ≈ 0.15) into their row-tint colors, which
    /// would make ribbons invisible if multiplied through.
    private func ribbonColor(_ hex: HexColor, opacity: Double) -> Color {
        Color(red: hex.red, green: hex.green, blue: hex.blue, opacity: opacity)
    }
}
