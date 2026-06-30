import '../theme/app_theme.dart'; 
import 'package:flutter/material.dart';
import 'active_filter.dart';
import 'filter_chip_bar.dart';

// ── FilterFormConfig ──────────────────────────────────────────────────────────

/// Declarative configuration describing what a filter form shows.
/// Pass this once per screen; it never changes at runtime.
class FilterFormConfig {
  final String title;
  final bool showDateRange;
  final bool showTextSearch;
  final String? textSearchHint;
  final List<FilterDefinition>? dynamicFields;

  const FilterFormConfig({
    required this.title,
    this.showDateRange = true,
    this.showTextSearch = true,
    this.textSearchHint,
    this.dynamicFields,
  });
}

// ── FilterFormState ───────────────────────────────────────────────────────────

/// Immutable value object holding the current filter state.
/// Returned by [FilterSheet.show] and stored in widget state.
class FilterFormState {
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String search;
  final List<ActiveFilter> dynamicFilters;

  const FilterFormState({
    this.dateFrom,
    this.dateTo,
    this.search = '',
    this.dynamicFilters = const [],
  });

  static const empty = FilterFormState();

  bool get isActive =>
      dateFrom != null ||
      dateTo != null ||
      search.isNotEmpty ||
      dynamicFilters.isNotEmpty;

  FilterFormState copyWith({
    DateTime? dateFrom,
    DateTime? dateTo,
    String? search,
    List<ActiveFilter>? dynamicFilters,
    bool clearDate = false,
    bool clearSearch = false,
  }) =>
      FilterFormState(
        dateFrom: clearDate ? null : (dateFrom ?? this.dateFrom),
        dateTo: clearDate ? null : (dateTo ?? this.dateTo),
        search: clearSearch ? '' : (search ?? this.search),
        dynamicFilters: dynamicFilters ?? this.dynamicFilters,
      );

  /// Human-readable summary label for the compact filter chip.
  String get summaryLabel {
    final parts = <String>[];
    if (dateFrom != null || dateTo != null) {
      final from = _fmt(dateFrom) ?? '…';
      final to   = _fmt(dateTo)   ?? '…';
      parts.add('$from → $to');
    }
    if (search.isNotEmpty) parts.add('"$search"');
    for (final f in dynamicFilters) {
      parts.add('${f.label}: ${f.displayValue}');
    }
    return parts.join(' · ');
  }

  // ── Local filtering ───────────────────────────────────────────────────────

  /// All dynamic filters — applied locally to loaded data.
  /// Call matchesAllFilters(record, state.toLocalFilters()) on the loaded list.
  List<ActiveFilter> toLocalFilters([FilterFormConfig? _]) => dynamicFilters;

  /// Query params to send to the backend (date range + text search only).
  Map<String, String> toQueryParams([FilterFormConfig? _]) {
    final p = <String, String>{};
    if (dateFrom != null) p['date_from'] = _fmt(dateFrom)!;
    if (dateTo   != null) p['date_to']   = _fmt(dateTo)!;
    if (search.isNotEmpty) p['search'] = search;
    return p;
  }

  /// Pipe-delimited key for Riverpod `FutureProvider.family`.
  /// Only the date range is included — the provider re-fetches when the user
  /// taps the Load button (which changes the date range). All other filters
  /// are applied locally without a re-fetch.
  String toProviderKey([FilterFormConfig? _]) =>
      '${_fmt(dateFrom) ?? ''}|${_fmt(dateTo) ?? ''}';

  static String? _fmt(DateTime? d) {
    if (d == null) return null;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

// ── FilterBar ─────────────────────────────────────────────────────────────────

/// Compact single-row bar to embed at the top of any screen.
/// Shows: label or active-filter chip + optional trailing widgets + tune/load buttons.
///
/// [onChanged] — called immediately when filter changes (local filtering, no re-fetch).
/// [onLoad]    — called when the user taps the sync/load button (triggers backend re-fetch).
class FilterBar extends StatelessWidget {
  final FilterFormConfig config;
  final FilterFormState state;
  final ValueChanged<FilterFormState> onChanged;
  final VoidCallback? onLoad;

  /// Optional widgets shown between the label and the buttons
  /// (e.g. inline totals: ₹approved, ₹pending).
  final List<Widget>? trailing;

  const FilterBar({
    super.key,
    required this.config,
    required this.state,
    required this.onChanged,
    this.onLoad,
    this.trailing,
  });

  Future<void> _openSheet(BuildContext ctx) async {
    final result = await FilterSheet.show(ctx, config, state);
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF4F6FA),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        // Active filter chip or placeholder label
        Expanded(
          child: GestureDetector(
            onTap: () => _openSheet(context),
            child: state.isActive
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF2EA),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.4)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.filter_alt, size: 14,
                          color: AppColors.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          state.summaryLabel,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.primary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => onChanged(FilterFormState.empty),
                        child: const Icon(Icons.close, size: 14,
                            color: AppColors.primary),
                      ),
                    ]),
                  )
                : Text(
                    'All records',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
          ),
        ),

        // Trailing widgets (totals etc.)
        if (trailing != null) ...[
          const SizedBox(width: 8),
          ...trailing!,
        ],

        const SizedBox(width: 8),

        // Tune button
        GestureDetector(
          onTap: () => _openSheet(context),
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: state.isActive
                  ? AppColors.primary
                  : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.tune,
              size: 18,
              color: state.isActive ? Colors.white : Colors.grey.shade600,
            ),
          ),
        ),

        // Load from server button (only shown when onLoad is wired)
        if (onLoad != null) ...[
          const SizedBox(width: 6),
          Tooltip(
            message: 'Load from server',
            child: GestureDetector(
              onTap: onLoad,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Icon(Icons.sync, size: 18, color: Colors.blue.shade700),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

// ── FilterSheet ───────────────────────────────────────────────────────────────

/// The filter bottom sheet. Open via [FilterSheet.show].
class FilterSheet extends StatefulWidget {
  final FilterFormConfig config;
  final FilterFormState initial;

  const FilterSheet._({required this.config, required this.initial});

  /// Opens the filter sheet and returns the new [FilterFormState] when applied,
  /// or `null` if dismissed without applying.
  static Future<FilterFormState?> show(
    BuildContext context,
    FilterFormConfig config,
    FilterFormState current,
  ) {
    return showModalBottomSheet<FilterFormState>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) =>
          FilterSheet._(config: config, initial: current),
    );
  }

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late FilterFormState _state;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _state = widget.initial;
    _searchCtrl.text = _state.search;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _state.dateFrom != null && _state.dateTo != null
          ? DateTimeRange(start: _state.dateFrom!, end: _state.dateTo!)
          : null,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme:
                const ColorScheme.light(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _state = _state.copyWith(
            dateFrom: picked.start,
            dateTo: picked.end,
          ));
    }
  }

  void _applyAndClose() {
    Navigator.of(context).pop(
      _state.copyWith(search: _searchCtrl.text.trim()),
    );
  }

  void _clearAll() {
    Navigator.of(context).pop(FilterFormState.empty);
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final hasDynamic = config.dynamicFields?.isNotEmpty ?? false;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
        builder: (_, scrollCtrl) => Column(children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
            child: Row(children: [
              const Icon(Icons.tune, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(config.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18)),
              ),
              if (_state.isActive || _searchCtrl.text.isNotEmpty)
                TextButton(
                  onPressed: _clearAll,
                  child: const Text('Clear all',
                      style: TextStyle(color: Colors.red)),
                ),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context)),
            ]),
          ),
          const Divider(height: 1),

          // Scrollable body
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              children: [

                // ── Text search ───────────────────────────────────────────
                if (config.showTextSearch) ...[
                  _SectionLabel('Search'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchCtrl,
                    autofocus: false,
                    decoration: InputDecoration(
                      hintText:
                          config.textSearchHint ?? 'Search…',
                      prefixIcon: const Icon(Icons.search_outlined,
                          size: 18),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: ValueListenableBuilder(
                        valueListenable: _searchCtrl,
                        builder: (_, v, child) =>
                            v.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close, size: 16),
                                    onPressed: () => _searchCtrl.clear())
                                : const SizedBox.shrink(),
                      ),
                    ),
                    onSubmitted: (_) => _applyAndClose(),
                  ),
                  const SizedBox(height: 20),
                ],

                // ── Date range ────────────────────────────────────────────
                if (config.showDateRange) ...[
                  _SectionLabel('Date Range'),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _pickDateRange,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: _state.dateFrom != null
                            ? const Color(0xFFEAF2EA)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: _state.dateFrom != null
                                ? AppColors.primary
                                : Colors.grey.shade300),
                      ),
                      child: Row(children: [
                        Icon(Icons.date_range_outlined,
                            size: 18,
                            color: _state.dateFrom != null
                                ? AppColors.primary
                                : Colors.grey),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _state.dateFrom != null
                                ? '${FilterFormState._fmt(_state.dateFrom)} → ${FilterFormState._fmt(_state.dateTo)}'
                                : 'All dates — tap to filter',
                            style: TextStyle(
                                fontSize: 14,
                                color: _state.dateFrom != null
                                    ? AppColors.primary
                                    : Colors.grey),
                          ),
                        ),
                        if (_state.dateFrom != null)
                          GestureDetector(
                            onTap: () => setState(
                                () => _state = _state.copyWith(clearDate: true)),
                            child: const Icon(Icons.close,
                                size: 16, color: Colors.grey),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // ── Dynamic field filters ─────────────────────────────────
                if (hasDynamic) ...[
                  _SectionLabel('Filters'),
                  const SizedBox(height: 8),
                  // Embed FilterChipBar inline (scrolls within the sheet)
                  _InlineFilterChipBar(
                    definitions: config.dynamicFields!,
                    activeFilters: _state.dynamicFilters,
                    onAdd: (f) => setState(() => _state = _state.copyWith(
                        dynamicFilters: [
                          ..._state.dynamicFilters
                              .where((e) => e.field != f.field),
                          f,
                        ])),
                    onRemove: (f) => setState(() => _state = _state.copyWith(
                        dynamicFilters: _state.dynamicFilters
                            .where((e) => e.field != f.field)
                            .toList())),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Apply button ──────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _applyAndClose,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Apply Filter',
                        style: TextStyle(fontSize: 15)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ]),
      );
  }
}

// ── Inline FilterChipBar (no horizontal scroll wrapper needed inside sheet) ───

class _InlineFilterChipBar extends StatelessWidget {
  final List<FilterDefinition> definitions;
  final List<ActiveFilter> activeFilters;
  final void Function(ActiveFilter) onAdd;
  final void Function(ActiveFilter) onRemove;

  const _InlineFilterChipBar({
    required this.definitions,
    required this.activeFilters,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChipBar(
      availableFilters: definitions,
      activeFilters: activeFilters,
      onAdd: onAdd,
      onRemove: onRemove,
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Colors.black87),
      );
}
