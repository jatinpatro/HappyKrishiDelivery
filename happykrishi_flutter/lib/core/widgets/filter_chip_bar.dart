import 'package:flutter/material.dart';
import 'active_filter.dart';

Color _chipColor(FilterType type) => switch (type) {
      FilterType.select => Colors.orange,
      FilterType.number => const Color(0xFF0277BD),
      FilterType.text => const Color(0xFF2E7D32),
    };

IconData _typeIcon(FilterType t) => switch (t) {
      FilterType.select => Icons.list_alt,
      FilterType.number => Icons.tag,
      FilterType.text => Icons.text_fields,
    };

String _typeHint(FilterType t) => switch (t) {
      FilterType.select => 'Choose an option',
      FilterType.number => 'Number with operator',
      FilterType.text => 'Type to search',
    };

String _opLabel(FilterOp op) => switch (op) {
      FilterOp.gte => '≥',
      FilterOp.lte => '≤',
      FilterOp.equals => '=',
      FilterOp.contains => 'contains',
    };

// ── Public widget ─────────────────────────────────────────────────────────────

class FilterChipBar extends StatelessWidget {
  final List<FilterDefinition> availableFilters;
  final List<ActiveFilter> activeFilters;
  final void Function(ActiveFilter) onAdd;
  final void Function(ActiveFilter) onRemove;

  const FilterChipBar({
    super.key,
    required this.availableFilters,
    required this.activeFilters,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _AddFilterButton(
            count: activeFilters.length,
            onTap: () => _openSheet(context),
          ),
          ...activeFilters.map((f) {
            final def = availableFilters.firstWhere(
              (d) => d.field == f.field,
              orElse: () => FilterDefinition(
                  field: f.field, label: f.label, type: FilterType.text),
            );
            return Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _ActiveChip(
                  filter: f, color: _chipColor(def.type), onRemove: onRemove),
            );
          }),
        ]),
      ),
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => AddFilterSheet(
        availableFilters: availableFilters,
        activeFilters: activeFilters,
        onAdd: (f) {
          Navigator.pop(context);
          onAdd(f);
        },
      ),
    );
  }
}

// ── Internal widgets ──────────────────────────────────────────────────────────

class _AddFilterButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _AddFilterButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: count > 0 ? const Color(0xFFE8F5E9) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: count > 0
                  ? const Color(0xFF2E7D32)
                  : Colors.grey.shade300,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add,
                size: 14,
                color: count > 0
                    ? const Color(0xFF2E7D32)
                    : Colors.grey.shade600),
            const SizedBox(width: 4),
            Text('Add Filter',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: count > 0
                      ? const Color(0xFF2E7D32)
                      : Colors.grey.shade700,
                )),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$count',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ]),
        ),
      );
}

class _ActiveChip extends StatelessWidget {
  final ActiveFilter filter;
  final Color color;
  final void Function(ActiveFilter) onRemove;
  const _ActiveChip(
      {required this.filter, required this.color, required this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${filter.label}: ${filter.displayValue}',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => onRemove(filter),
            child: Icon(Icons.close, size: 14, color: color),
          ),
        ]),
      );
}

// ── Add Filter Sheet ──────────────────────────────────────────────────────────

class AddFilterSheet extends StatefulWidget {
  final List<FilterDefinition> availableFilters;
  final List<ActiveFilter> activeFilters;
  final void Function(ActiveFilter) onAdd;

  const AddFilterSheet({
    super.key,
    required this.availableFilters,
    required this.activeFilters,
    required this.onAdd,
  });

  @override
  State<AddFilterSheet> createState() => _AddFilterSheetState();
}

class _AddFilterSheetState extends State<AddFilterSheet> {
  FilterDefinition? _selected;
  FilterOp _op = FilterOp.gte;
  final _textCtrl = TextEditingController();
  String? _selectValue;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  bool _isActive(FilterDefinition def) =>
      widget.activeFilters.any((f) => f.field == def.field);

  ActiveFilter? _buildFilter() {
    final def = _selected;
    if (def == null) return null;
    switch (def.type) {
      case FilterType.text:
        final v = _textCtrl.text.trim();
        if (v.isEmpty) return null;
        return ActiveFilter(
            field: def.field,
            label: def.label,
            value: v,
            op: FilterOp.contains,
            displayValue: v);
      case FilterType.number:
        final n = num.tryParse(_textCtrl.text.trim());
        if (n == null) return null;
        return ActiveFilter(
            field: def.field,
            label: def.label,
            value: n,
            op: _op,
            displayValue: '${_opLabel(_op)} $n');
      case FilterType.select:
        final sv = _selectValue;
        if (sv == null) return null;
        return ActiveFilter(
            field: def.field,
            label: def.label,
            value: sv,
            op: FilterOp.equals,
            displayValue: sv);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.fromLTRB(0, 0, 0, MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const Text('Add Filter',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context)),
            ]),
          ),
          const Divider(height: 1),

          // ── Field list ─────────────────────────────────────────────────
          if (_selected == null)
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: widget.availableFilters.map((def) {
                  final active = _isActive(def);
                  return ListTile(
                    enabled: !active,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor:
                          _chipColor(def.type).withValues(alpha: 0.15),
                      child: Icon(_typeIcon(def.type),
                          size: 16, color: _chipColor(def.type)),
                    ),
                    title: Text(def.label,
                        style: TextStyle(
                            color: active ? Colors.grey : null,
                            fontWeight: FontWeight.w500)),
                    subtitle: Text(_typeHint(def.type),
                        style: const TextStyle(fontSize: 11)),
                    trailing: active
                        ? const Icon(Icons.check_circle,
                            color: Color(0xFF2E7D32), size: 18)
                        : const Icon(Icons.chevron_right,
                            color: Colors.grey, size: 18),
                    onTap: active
                        ? null
                        : () => setState(() {
                              _selected = def;
                              _op = FilterOp.gte;
                              _textCtrl.clear();
                              _selectValue = def.options?.first;
                            }),
                  );
                }).toList(),
              ),
            ),

          // ── Inline input ───────────────────────────────────────────────
          if (_selected != null)
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  TextButton.icon(
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: const Text('Back to fields'),
                    onPressed: () =>
                        setState(() { _selected = null; _textCtrl.clear(); }),
                    style: TextButton.styleFrom(
                        foregroundColor: Colors.grey.shade600,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  ),
                  const SizedBox(height: 12),
                  Text(_selected!.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 12),

                  // Number
                  if (_selected!.type == FilterType.number) ...[
                    Row(children: [
                      for (final op in [FilterOp.gte, FilterOp.lte, FilterOp.equals])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => setState(() => _op = op),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: _op == op
                                    ? const Color(0xFF0277BD)
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: _op == op
                                        ? const Color(0xFF0277BD)
                                        : Colors.grey.shade300),
                              ),
                              child: Text(_opLabel(op),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _op == op
                                        ? Colors.white
                                        : Colors.black87,
                                  )),
                            ),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _textCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: InputDecoration(
                        hintText: 'Enter value',
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      autofocus: true,
                    ),
                  ],

                  // Text
                  if (_selected!.type == FilterType.text) ...[
                    TextField(
                      controller: _textCtrl,
                      decoration: InputDecoration(
                        hintText: 'Contains…',
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      autofocus: true,
                    ),
                  ],

                  // Select
                  if (_selected!.type == FilterType.select) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: (_selected!.options ?? []).map((opt) {
                        final sel = _selectValue == opt;
                        return GestureDetector(
                          onTap: () => setState(() => _selectValue = opt),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: sel ? Colors.orange : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: sel
                                      ? Colors.orange
                                      : Colors.grey.shade300),
                            ),
                            child: Text(opt,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        sel ? Colors.white : Colors.black87)),
                          ),
                        );
                      }).toList(),
                    ),
                  ],

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final f = _buildFilter();
                        if (f != null) widget.onAdd(f);
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 46)),
                      child: const Text('Apply Filter'),
                    ),
                  ),
                ]),
              ),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}
