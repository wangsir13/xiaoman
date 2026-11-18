import SwiftUI

struct TransactionRow: View {

    let transaction: Transaction

    private var amountColor: Color {
        transaction.direction == .expense ? .primary : Color(red: 0.13, green: 0.62, blue: 0.36)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(String(transaction.category.prefix(1)))
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12), in: Circle())
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(transaction.title)
                        .font(.body)
                        .lineLimit(1)
                    if transaction.source != .other {
                        Text(transaction.source.title)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                Text("\(transaction.category) · \(DateFormatter.clock.string(from: transaction.occurredAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(transaction.displayAmount)
                .font(.system(.body, design: .rounded).weight(.medium))
                .foregroundStyle(amountColor)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}
