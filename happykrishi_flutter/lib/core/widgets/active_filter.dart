enum FilterOp { equals, contains, gte, lte }

enum FilterType { text, number, select }

class FilterDefinition {
  final String field;
  final String label;
  final FilterType type;
  final List<String>? options;
  const FilterDefinition(
      {required this.field,
      required this.label,
      required this.type,
      this.options});
}

class ActiveFilter {
  final String field;
  final String label;
  final dynamic value;
  final FilterOp op;
  final String displayValue;

  const ActiveFilter({
    required this.field,
    required this.label,
    required this.value,
    required this.op,
    required this.displayValue,
  });

  @override
  bool operator ==(Object other) =>
      other is ActiveFilter && other.field == field;

  @override
  int get hashCode => field.hashCode;
}

/// Returns true if [record] satisfies all [filters] (AND logic).
bool matchesAllFilters(
    Map<String, dynamic> record, List<ActiveFilter> filters) {
  for (final f in filters) {
    final raw = record[f.field];
    switch (f.op) {
      case FilterOp.contains:
        if (!(raw
                ?.toString()
                .toLowerCase()
                .contains((f.value as String).toLowerCase()) ??
            false)) return false;
      case FilterOp.equals:
        if (raw?.toString() != (f.value as String)) return false;
      case FilterOp.gte:
        if (((raw as num?)?.toDouble() ?? 0) < (f.value as num)) return false;
      case FilterOp.lte:
        if (((raw as num?)?.toDouble() ?? 0) > (f.value as num)) return false;
    }
  }
  return true;
}
