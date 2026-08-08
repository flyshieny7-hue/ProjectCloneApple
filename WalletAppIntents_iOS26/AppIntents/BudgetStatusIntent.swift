import AppIntents
import SwiftUI

@AssistantIntent(schema: .wallet.budgetStatus)
struct BudgetStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Budget Status"
    static var description: IntentDescription = "Check budget spending status"

    @Parameter(title: "Category", description: "Budget category", requestValueDialog: "Which budget category?")
    var category: BudgetCategoryEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("How's my \(.$category) budget?")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        if let specificCategory = category {
            return try await resultForBudget(specificCategory)
        }

        let budgets = WalletDataProvider.shared.budgets
        let totalSpent = budgets.reduce(0) { $0 + $1.spent }
        let totalLimit = budgets.reduce(0) { $0 + $1.limit }
        let overallPercent = totalLimit > 0 ? Int((totalSpent / totalLimit) * 100) : 0

        let dialog: LocalizedStringResource = "Overall, you've used \(overallPercent)% of your total budget. Here are your categories."

        return .result(
            dialog: dialog,
            view: BudgetOverviewView(budgets: budgets)
        )
    }

    private func resultForBudget(_ budget: BudgetCategoryEntity) async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let percent = budget.limit > 0 ? Int((budget.spent / budget.limit) * 100) : 0
        let remaining = budget.limit - budget.spent

        let statusText: String
        if percent >= 100 {
            statusText = "You've exceeded your \(budget.name) budget by \(abs(remaining), format: .currency(code: \"USD\"))."
        } else if percent >= 80 {
            statusText = "You're at \(percent)% of your \(budget.name) budget. Only \(remaining, format: .currency(code: \"USD\")) left."
        } else {
            statusText = "You're doing well on your \(budget.name) budget. You've spent \(percent)% so far."
        }

        let dialog = LocalizedStringResource(stringLiteral: statusText)

        return .result(
            dialog: dialog,
            view: BudgetDetailView(budget: budget)
        )
    }
}

struct BudgetOverviewView: View {
    let budgets: [BudgetCategoryEntity]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Budget Overview")
                .font(.headline)

            ForEach(budgets) { budget in
                BudgetRowView(budget: budget)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct BudgetRowView: View {
    let budget: BudgetCategoryEntity

    var percent: Double {
        budget.limit > 0 ? min(budget.spent / budget.limit, 1.0) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(budget.name, systemImage: budget.iconName)
                    .font(.subheadline.bold())

                Spacer()

                Text("\(Int(percent * 100))%")
                    .font(.caption.bold())
                    .foregroundStyle(percent > 0.9 ? .red : .primary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.gray.opacity(0.2))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(percent > 0.9 ? .red : percent > 0.75 ? .orange : .green)
                        .frame(width: geo.size.width * CGFloat(percent), height: 8)
                }
            }
            .frame(height: 8)
        }
    }
}

struct BudgetDetailView: View {
    let budget: BudgetCategoryEntity

    var percent: Double {
        budget.limit > 0 ? budget.spent / budget.limit : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: budget.iconName)
                    .font(.title)
                    .foregroundStyle(percent > 0.9 ? .red : .primary)

                VStack(alignment: .leading) {
                    Text(budget.name)
                        .font(.headline)
                    Text("Monthly Budget")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                VStack(alignment: .leading) {
                    Text("Spent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(budget.spent, format: .currency(code: "USD"))
                        .font(.subheadline.bold())
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("Remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(budget.limit - budget.spent, format: .currency(code: "USD"))
                        .font(.subheadline.bold())
                        .foregroundStyle(budget.spent > budget.limit ? .red : .primary)
                }
            }

            BudgetRowView(budget: budget)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
