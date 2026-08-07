import SwiftUI
import UIKit

struct DoodleStroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    var colorHex: String
    var width: CGFloat
    var isEraser: Bool

    var color: Color { isEraser ? .white : Color(hex: colorHex) }
    var uiColor: UIColor { isEraser ? .white : UIColor(Color(hex: colorHex)) }
}

struct DoodleScreen: View {
    var onFinish: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var strokes: [DoodleStroke] = []
    @State private var current: DoodleStroke?
    @State private var colorHex = "000000"
    @State private var width: CGFloat = 6
    @State private var isEraser = false
    @State private var canvasSize: CGSize = .zero

    private let palette = ["000000", "FFFFFF", "E74C3C", "E67E22", "F1C40F", "27AE60", "2980B9", "8E44AD"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                canvas
                controls
            }
            .navigationTitle("涂鸦")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { finish() }
                        .disabled(strokes.isEmpty && current == nil)
                }
            }
        }
    }

    private var canvas: some View {
        GeometryReader { geo in
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                for stroke in strokes {
                    draw(stroke, in: &context)
                }
                if let current {
                    draw(current, in: &context)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if current == nil {
                            current = DoodleStroke(points: [value.startLocation],
                                                   colorHex: colorHex,
                                                   width: width,
                                                   isEraser: isEraser)
                        }
                        current?.points.append(value.location)
                    }
                    .onEnded { _ in
                        if let stroke = current, stroke.points.count > 1 {
                            strokes.append(stroke)
                        } else if let stroke = current {
                            strokes.append(stroke)
                        }
                        current = nil
                    }
            )
            .onAppear { canvasSize = geo.size }
            .onChange(of: geo.size) { canvasSize = $0 }
        }
        .background(Color.white)
    }

    private func draw(_ stroke: DoodleStroke, in context: inout GraphicsContext) {
        guard let first = stroke.points.first else { return }
        if stroke.points.count == 1 {
            let r = stroke.width / 2
            let rect = CGRect(x: first.x - r, y: first.y - r, width: stroke.width, height: stroke.width)
            context.fill(Path(ellipseIn: rect), with: .color(stroke.color))
            return
        }
        var path = Path()
        path.move(to: first)
        for point in stroke.points.dropFirst() {
            path.addLine(to: point)
        }
        context.stroke(path,
                       with: .color(stroke.color),
                       style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round))
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ForEach(palette, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(Color.gray.opacity(0.4), lineWidth: 1))
                        .overlay(
                            Circle()
                                .stroke(Color.accentColor, lineWidth: colorHex == hex && !isEraser ? 2.5 : 0)
                                .padding(-3)
                        )
                        .onTapGesture {
                            colorHex = hex
                            isEraser = false
                            Haptics.selection()
                        }
                }
            }

            HStack(spacing: 16) {
                Image(systemName: "scribble")
                Slider(value: $width, in: 1...30)
                Button {
                    isEraser.toggle()
                } label: {
                    Image(systemName: isEraser ? "eraser.fill" : "eraser")
                }
                Button {
                    if !strokes.isEmpty { strokes.removeLast() }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(strokes.isEmpty)
                Button {
                    strokes.removeAll()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(strokes.isEmpty)
            }
            .font(.system(size: 18))
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 14)
        .background(XDTheme.card)
    }

    private func finish() {
        let size = canvasSize
        guard size.width > 1, size.height > 1, !strokes.isEmpty else {
            Toast.shared.error("还没画东西")
            return
        }
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            for stroke in strokes {
                guard let first = stroke.points.first else { continue }
                let cg = ctx.cgContext
                cg.setStrokeColor(stroke.uiColor.cgColor)
                cg.setFillColor(stroke.uiColor.cgColor)
                cg.setLineWidth(stroke.width)
                cg.setLineCap(.round)
                cg.setLineJoin(.round)
                if stroke.points.count == 1 {
                    let r = stroke.width / 2
                    cg.fillEllipse(in: CGRect(x: first.x - r, y: first.y - r,
                                              width: stroke.width, height: stroke.width))
                } else {
                    cg.beginPath()
                    cg.move(to: first)
                    for point in stroke.points.dropFirst() { cg.addLine(to: point) }
                    cg.strokePath()
                }
            }
        }
        onFinish(image)
        dismiss()
    }
}
