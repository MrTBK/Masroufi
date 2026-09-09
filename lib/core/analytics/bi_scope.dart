import '../../data/database/app_db.dart';
import '../../data/repositories/analytics_repo.dart';
import '../../data/repositories/budgets_repo.dart';
import '../../data/repositories/categories_repo.dart';
import '../../data/repositories/category_budgets_repo.dart';
import '../../data/repositories/debts_repo.dart';
import '../../data/repositories/recurring_repo.dart';
import '../../data/repositories/wallets_repo.dart';
import 'kpi.dart';

/// BI filter bar selection. All id lists are explicit: the UI expands a
/// chosen parent category to parent-plus-children via [expandCategory]
/// before loading, so the engine never guesses hierarchy intent.
/// Empty [walletIds] means all wallets; null [categoryIds] means all
/// categories; null [type] means expense plus income.
class BiFilter {
  final DateTime from;
  final DateTime to;
  final List<String> walletIds;
  final List<String>? categoryIds;
  final String? type;
  const BiFilter({
    required this.from,
    required this.to,
    this.walletIds = const [],
    this.categoryIds,
    this.type,
  });

  /// Expand a selected category to itself plus direct children (single
  /// level, matching the schema). Null selection stays null (all).
  static List<String>? expandCategory(
    List<Category> all,
    String? selectedId,
  ) {
    if (selectedId == null) return null;
    return [
      selectedId,
      for (final c in all)
        if (c.parentId == selectedId) c.id,
    ];
  }
}

/// One fully-computed BI snapshot for a [BiFilter] scope. Every
/// visualization on the Analytics page reads this single record, so the
/// global filter bar recalculates the whole page in one load. Ledger
/// analytics only; budget rows are month-anchored to the month
/// containing the last included instant (`to` minus 1ms, so a
/// [Sept 1, Oct 1) scope anchors to September). All int millimes.
typedef BiBudgetRow = ({
  String categoryId,
  int budget,
  int spent,
});

typedef BiSnapshot = ({
  DateTime from,
  DateTime to,
  int income,
  int expense,
  int txnCount,
  int? savingsRate,
  ({int diff, int pct})? growth,
  int? yoyExpense,
  Map<String?, int> byCategory,
  Map<String?, int> incomeByCat,
  Map<String, int> byPriority,
  Map<String, int> byWallet,
  List<MonthSlice> trend,
  List<Category> cats,
  List<Wallet> wallets,
  int monthSpent,
  int? monthBudget,
  int monthlyObligations,
  int? obligationsShare,
  int openOwed,
  int overdueDebts,
  List<BiBudgetRow> budgetRows,
  int? overallBudget,
  int overallSpent,
});

/// Single-batched BI loader over the existing repositories. Query
/// discipline: indexed SUM/COUNT only, no full scans; per-wallet and
/// per-month loops are bounded by wallet count (small) and a fixed
/// 6-month trend window.
class FilteredAnalytics {
  final AnalyticsRepo analytics;
  final WalletsRepo wallets;
  final CategoriesRepo categories;
  final RecurringRepo recurring;
  final DebtsRepo debts;
  final BudgetsRepo budgets;
  final CategoryBudgetsRepo catBudgets;
  FilteredAnalytics({
    required this.analytics,
    required this.wallets,
    required this.categories,
    required this.recurring,
    required this.debts,
    required this.budgets,
    required this.catBudgets,
  });

  /// Normalize an active recurring rule to a monthly millime estimate.
  /// Int-only factors: daily x30, weekly x30/7, monthly x1, yearly /12.
  static int monthlyRuleEstimate(RecurringRule r) {
    if (r.type != 'expense') return 0;
    return switch (r.frequency) {
      'daily' => r.amountMillimes * 30,
      'weekly' => r.amountMillimes * 30 ~/ 7,
      'yearly' => r.amountMillimes ~/ 12,
      _ => r.amountMillimes,
    };
  }

  Future<BiSnapshot> load(BiFilter f, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final wids = f.walletIds;
    final results = await Future.wait([
      analytics.incomeTotalW(wids, f.from, f.to),
      analytics.expenseTotalW(wids, f.from, f.to),
      analytics.txnCount(
        walletIds: wids.isEmpty ? null : wids,
        categoryIds: f.categoryIds,
        type: f.type,
        from: f.from,
        to: f.to,
      ),
      analytics.expenseByCategory(f.from, f.to, walletIds: wids),
      analytics.incomeByCategory(f.from, f.to, walletIds: wids),
      analytics.expenseByPriority(f.from, f.to),
      categories.all(includeArchived: true),
      wallets.all(includeArchived: false),
    ]);
    final income = results[0] as int;
    final expense = results[1] as int;
    final byCat = results[3] as Map<String?, int>;
    final incomeByCat = results[4] as Map<String?, int>;
    final cats = results[6] as List<Category>;
    final allWallets = results[7] as List<Wallet>;

    // Previous equal-length range for growth.
    final span = f.to.difference(f.from);
    final prevEnd = f.from;
    final prevStart = f.from.subtract(span);
    final prevExpense = await analytics.expenseTotalW(wids, prevStart, prevEnd);

    // YoY only when the scope is exactly one calendar month.
    int? yoy;
    final monthStart = DateTime(f.from.year, f.from.month, 1);
    final nextMonth = f.from.month == 12
        ? DateTime(f.from.year + 1, 1, 1)
        : DateTime(f.from.year, f.from.month + 1, 1);
    if (f.from == monthStart && f.to == nextMonth) {
      final last = await analytics.sameMonthLastYear(
        f.from.year,
        f.from.month,
      );
      yoy = last.expense;
    }

    // Per-wallet expense (bounded by wallet count).
    final byWallet = <String, int>{};
    for (final w in allWallets) {
      byWallet[w.id] = await analytics.expenseTotalW([w.id], f.from, f.to);
    }

    // Filtered 6-month trend ending at the scope's last included month.
    final anchor = f.to.subtract(const Duration(milliseconds: 1));
    final trend = <MonthSlice>[];
    var y = anchor.year;
    var m = anchor.month;
    for (var i = 0; i < 6; i++) {
      final s = DateTime(y, m, 1);
      final e = m == 12 ? DateTime(y + 1, 1, 1) : DateTime(y, m + 1, 1);
      trend.add((
        year: y,
        month: m,
        income: await analytics.incomeTotalW(wids, s, e),
        expense: await analytics.expenseTotalW(wids, s, e),
      ));
      m--;
      if (m < 1) {
        m = 12;
        y--;
      }
    }

    // Current-month pace inputs (scoped).
    final curStart = DateTime(at.year, at.month, 1);
    final monthSpent = await analytics.expenseTotalW(wids, curStart, at);
    final overall = await budgets.getMonth(at.year, at.month);

    // Obligations: normalized recurring + open-owed service horizon.
    // Documented estimate: open 'owe' principal spread over 12 months.
    var monthlyOblig = 0;
    for (final r in await recurring.all(activeOnly: true)) {
      monthlyOblig += monthlyRuleEstimate(r);
    }
    final openDebts = await debts.all(openOnly: true);
    var openOwed = 0;
    var overdue = 0;
    for (final d in openDebts) {
      if (d.direction == 'owe') {
        final left = await debts.remaining(d.id);
        openOwed += left;
        if (d.dueDate != null && d.dueDate!.isBefore(at)) overdue++;
      }
    }
    monthlyOblig += openOwed ~/ 12;
    final obligShare = income > 0
        ? ((monthlyOblig * 100 + income ~/ 2) ~/ income)
        : null;

    // Budget rows anchored to the same month.
    final by = anchor.year;
    final bm = anchor.month;
    final overallB = await budgets.getMonth(by, bm);
    final overallSpent = await budgets.spent(by, bm);
    final budgetRows = <BiBudgetRow>[];
    for (final cb in await catBudgets.forMonth(by, bm)) {
      budgetRows.add((
        categoryId: cb.categoryId,
        budget: cb.amountMillimes,
        spent: await catBudgets.spent(cb.categoryId, by, bm),
      ));
    }

    return (
      from: f.from,
      to: f.to,
      income: income,
      expense: expense,
      txnCount: results[2] as int,
      savingsRate: Kpi.savingsRate(
        incomeMillimes: income,
        expenseMillimes: expense,
      ),
      growth: Kpi.expenseGrowth(current: expense, previous: prevExpense),
      yoyExpense: yoy,
      byCategory: byCat,
      incomeByCat: incomeByCat,
      byPriority: results[5] as Map<String, int>,
      byWallet: byWallet,
      trend: trend.reversed.toList(),
      cats: cats,
      wallets: allWallets,
      monthSpent: monthSpent,
      monthBudget: overall?.amountMillimes,
      monthlyObligations: monthlyOblig,
      obligationsShare: obligShare,
      openOwed: openOwed,
      overdueDebts: overdue,
      budgetRows: budgetRows,
      overallBudget: overallB?.amountMillimes,
      overallSpent: overallSpent,
    );
  }
}
