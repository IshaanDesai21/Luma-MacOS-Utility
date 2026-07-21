import SwiftUI

/// A native-looking month calendar with previous/next navigation.
struct MonthCalendarView: View {
    /// `.panel` styles itself as a floating glass card; `.popover` renders plain
    /// so the hosting `NSPopover` provides the background (no doubled chrome).
    enum Style { case panel, popover }

    var style: Style = .panel
    var onClose: (() -> Void)?

    @State private var monthAnchor = Date()

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        VStack(spacing: 12) {
            header
            weekdayRow
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    dayCell(day)
                }
            }
        }
        .padding(style == .panel ? 18 : 16)
        .frame(width: 280)
        .modifier(CardBackground(style: style))
    }

    /// Only the floating panel draws its own glass card + shadow.
    private struct CardBackground: ViewModifier {
        let style: Style
        func body(content: Content) -> some View {
            switch style {
            case .popover:
                content
            case .panel:
                content
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                    .padding(16)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(monthTitle)
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
            Button { monthAnchor = Date() } label: { Image(systemName: "circle.fill").font(.system(size: 7)) }
                .buttonStyle(.borderless)
                .help("Today")
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
            if let onClose {
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 2) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(_ day: Date?) -> some View {
        Group {
            if let day {
                let isToday = calendar.isDateInToday(day)
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 12, weight: isToday ? .bold : .regular))
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .background {
                        if isToday {
                            Circle().fill(.tint).frame(width: 26, height: 26)
                        }
                    }
                    .foregroundStyle(isToday ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            } else {
                Color.clear.frame(maxWidth: .infinity, minHeight: 28)
            }
        }
    }

    // MARK: - Data

    private var monthTitle: String {
        monthAnchor.formatted(.dateTime.month(.wide).year())
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var days: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: monthAnchor),
              let firstWeekday = calendar.dateComponents([.weekday], from: monthInterval.start).weekday
        else { return [] }

        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: monthAnchor)?.count ?? 0

        var result: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for offset in 0..<dayCount {
            result.append(calendar.date(byAdding: .day, value: offset, to: monthInterval.start))
        }
        return result
    }

    private func step(_ months: Int) {
        if let next = calendar.date(byAdding: .month, value: months, to: monthAnchor) {
            monthAnchor = next
        }
    }
}
