import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../data/repositories/transaction_repository.dart';
import '../providers.dart';
import '../widgets/export_sheet.dart';
import 'review_screen.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final f = ref.read(historyFilterProvider);
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: f.from != null && f.to != null ? DateTimeRange(start: f.from!, end: f.to!) : null,
    );
    if (r != null) {
      ref.read(historyFilterProvider.notifier).state = f.copyWith(from: r.start, to: r.end);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(historyFilterProvider);
    final list = ref.watch(transactionsProvider);
    final settings = ref.watch(settingsProvider);
    final categories = ref.watch(categoriesProvider).valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat'),
        actions: [
          IconButton(
            tooltip: 'Ekspor ke Excel',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () => showExportSheet(context),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Cari merchant, deskripsi, catatan…',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _search.clear();
                        ref.read(historyFilterProvider.notifier).state = filter.copyWith(query: '');
                      }),
            ),
            onChanged: (v) => ref.read(historyFilterProvider.notifier).state = filter.copyWith(query: v),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              ActionChip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: Text(filter.from == null
                    ? 'Tanggal'
                    : '${Fmt.date(filter.from!, settings)} – ${Fmt.date(filter.to!, settings)}'),
                onPressed: _pickRange,
              ),
              const SizedBox(width: 8),
              for (final c in categories) ...[
                FilterChip(
                  label: Text(c.name),
                  selected: filter.category == c.name,
                  onSelected: (sel) => ref.read(historyFilterProvider.notifier).state =
                      sel ? filter.copyWith(category: c.name) : filter.copyWith(clearCategory: true),
                ),
                const SizedBox(width: 8),
              ],
              if (!filter.isEmpty)
                TextButton(
                  onPressed: () {
                    _search.clear();
                    ref.read(historyFilterProvider.notifier).state = const TransactionFilter();
                  },
                  child: const Text('Reset'),
                ),
            ],
          ),
        ),
        Expanded(
          child: list.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Gagal memuat: $e')),
            data: (items) => items.isEmpty
                ? const Center(child: Text('Tidak ada transaksi'))
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final t = items[i];
                      return Dismissible(
                        key: ValueKey(t.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Theme.of(context).colorScheme.error,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (_) async =>
                            await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Hapus transaksi?'),
                                content: Text('${t.merchant} • ${Fmt.money(t.total, settings)}\n'
                                    '${t.synced ? "Catatan: baris di Google Sheets TIDAK ikut terhapus." : ""}'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
                                ],
                              ),
                            ) ??
                            false,
                        onDismissed: (_) => ref.read(transactionActionsProvider).delete(t.id),
                        child: ListTile(
                          title: Text(t.merchant),
                          subtitle: Text('${Fmt.date(t.date, settings)} • ${t.category}'
                              '${t.description.isEmpty ? "" : "\n${t.description}"}'),
                          isThreeLine: t.description.isNotEmpty,
                          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(Fmt.money(t.total, settings), style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (settings.hasSpreadsheet)
                              Icon(t.synced ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined, size: 16),
                          ]),
                          onTap: () => Navigator.push(
                              context, MaterialPageRoute(builder: (_) => ReviewScreen(existing: t))),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}
