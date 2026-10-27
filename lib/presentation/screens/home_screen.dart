import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../providers.dart';
import 'review_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(homeSummaryProvider);
    final settings = ref.watch(settingsProvider);
    final pending = ref.watch(pendingSyncCountProvider).valueOrNull ?? 0;
    final sync = ref.watch(syncControllerProvider);
    final monthName = DateFormat('MMMM yyyy', 'id_ID').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text(kAppName)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(homeSummaryProvider);
          await ref.read(syncControllerProvider.notifier).syncNow();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            summary.when(
              loading: () => const Card(child: SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))),
              error: (e, _) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('Gagal memuat: $e'))),
              data: (s) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Pengeluaran $monthName', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Text(Fmt.money(s.monthTotal, settings), style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text('${s.monthCount} transaksi'),
                  ]),
                ),
              ),
            ),
            if (settings.hasSpreadsheet)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ListTile(
                  leading: sync.running
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(pending == 0 ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined),
                  title: Text(pending == 0 ? 'Semua tersinkron ke Google Sheets' : '$pending menunggu sinkronisasi'),
                  subtitle: sync.message == null ? null : Text(sync.message!),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const ReviewScreen())), // input manual
              icon: const Icon(Icons.edit_note),
              label: const Text('Input manual tanpa foto'),
            ),
            const SizedBox(height: 16),
            Text('Terakhir', style: Theme.of(context).textTheme.titleMedium),
            ...summary.maybeWhen<List<Widget>>(
              data: (s) => s.recent.isEmpty
                  ? <Widget>[const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Belum ada transaksi. Tekan "Scan struk".')))]
                  : s.recent
                      .map<Widget>((t) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(t.merchant),
                            subtitle: Text('${Fmt.date(t.date, settings)} • ${t.category}'),
                            trailing: Text(Fmt.money(t.total, settings)),
                            onTap: () => Navigator.push(
                                context, MaterialPageRoute(builder: (_) => ReviewScreen(existing: t))),
                          ))
                      .toList(),
              orElse: () => const <Widget>[],
            ),
          ],
        ),
      ),
    );
  }
}
