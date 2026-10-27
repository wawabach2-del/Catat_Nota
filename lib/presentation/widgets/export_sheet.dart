import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../providers.dart';

void showExportSheet(BuildContext context) {
  showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => const _ExportSheet());
}

class _ExportSheet extends ConsumerStatefulWidget {
  const _ExportSheet();

  @override
  ConsumerState<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<_ExportSheet> {
  bool _onlyNew = false;
  bool _busy = false;

  Future<void> _run({required bool append}) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _busy = true);
    try {
      File? existing;
      if (append) {
        final pick = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx']);
        final path = pick?.files.single.path;
        if (path == null) {
          setState(() => _busy = false);
          return;
        }
        existing = File(path);
      }

      // Pakai filter yang sedang aktif di Riwayat (tanggal/kategori/pencarian).
      final filter = ref.read(historyFilterProvider);
      final repo = ref.read(transactionRepoProvider);
      final items = (await repo.query(filter, onlyNotExported: _onlyNew)).reversed.toList(); // lama -> baru
      if (items.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('Tidak ada transaksi untuk diekspor')));
        setState(() => _busy = false);
        return;
      }

      final settings = ref.read(settingsProvider);
      final file = await ref.read(excelServiceProvider).export(items, appendTo: existing, sheetName: settings.sheetName);
      await repo.markExported(items.map((e) => e.id));

      nav.pop();
      await Share.shareXFiles([XFile(file.path)], subject: 'Pembukuan');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Ekspor gagal: $e')));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(historyFilterProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Ekspor ke Excel', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(filter.isEmpty ? 'Semua transaksi' : 'Sesuai filter Riwayat yang aktif'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hanya yang belum pernah diekspor'),
            subtitle: const Text('Mencegah baris ganda saat menambahkan ke file lama'),
            value: _onlyNew,
            onChanged: (v) => setState(() => _onlyNew = v),
          ),
          if (_busy)
            const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
          else ...[
            FilledButton.icon(
              onPressed: () => _run(append: false),
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Buat file .xlsx baru'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _run(append: true),
              icon: const Icon(Icons.playlist_add),
              label: const Text('Tambahkan ke file .xlsx yang ada…'),
            ),
          ],
        ]),
      ),
    );
  }
}
