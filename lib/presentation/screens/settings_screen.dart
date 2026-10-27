import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../domain/models/category.dart';
import '../../services/sheets/google_sheets_service.dart';
import '../providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _connected = false;
  String? _email;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final auth = ref.read(googleAuthProvider);
    final ok = ref.read(settingsProvider).hasSpreadsheet && await auth.restore();
    if (mounted) setState(() {
      _connected = ok;
      _email = auth.email;
    });
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // ───── Google Sheets ─────
  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      final email = await ref.read(googleAuthProvider).connect();
      if (email == null) {
        _toast('Login Google dibatalkan');
      } else {
        setState(() {
          _connected = true;
          _email = email;
        });
        await _chooseSpreadsheet();
      }
    } catch (e) {
      _toast('Gagal menghubungkan: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    await ref.read(googleAuthProvider).disconnect();
    await ref.read(syncQueueRepoProvider).clear();
    final s = ref.read(settingsProvider);
    await ref.read(settingsProvider.notifier).update(s.withSpreadsheet());
    ref.invalidate(pendingSyncCountProvider);
    if (mounted) setState(() {
      _connected = false;
      _email = null;
    });
    _toast('Google Sheets diputus dan akses dicabut');
  }

  Future<void> _chooseSpreadsheet() async {
    final choice = await showDialog<_SheetChoice>(context: context, builder: (_) => const _SheetDialog());
    if (choice == null) return;

    setState(() => _busy = true);
    try {
      final client = await ref.read(googleAuthProvider).authenticatedClient();
      if (client == null) throw 'Sesi Google tidak valid';
      try {
        final svc = ref.read(sheetsServiceProvider);
        final s = ref.read(settingsProvider);
        final SpreadsheetRef ref0 = choice.createNew
            ? await svc.create(client, choice.value, s.sheetName)
            : await svc.prepare(client, choice.value, s.sheetName);
        await ref.read(settingsProvider.notifier).update(s.withSpreadsheet(id: ref0.id, title: ref0.title));
        _toast('Terhubung ke "${ref0.title}"');
      } finally {
        client.close();
      }
      // Kirim riwayat lama yang belum pernah tersinkron.
      final n = await ref.read(syncQueueRepoProvider).enqueueAllUnsynced();
      ref.invalidate(pendingSyncCountProvider);
      if (n > 0) ref.read(syncControllerProvider.notifier).syncNow();
    } catch (e) {
      _toast('Tidak bisa mengakses spreadsheet: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ───── Kategori ─────
  Future<void> _editCategory([Category? c]) async {
    final name = TextEditingController(text: c?.name ?? '');
    final kw = TextEditingController(text: c?.keywords.join(', ') ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(c == null ? 'Kategori baru' : 'Edit kategori'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nama')),
          TextField(
            controller: kw,
            decoration: const InputDecoration(labelText: 'Kata kunci (pisah koma)', helperText: 'Untuk menebak kategori dari teks struk'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final repo = ref.read(categoryRepoProvider);
    final keywords = kw.text.split(',').map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toList();
    try {
      await repo.upsert((c ?? Category(id: const Uuid().v4(), name: '', colorValue: 0xFF607D8B))
          .copyWith(name: name.text.trim(), keywords: keywords));
      ref.invalidate(categoriesProvider);
    } catch (_) {
      _toast('Nama kategori sudah dipakai');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final categories = ref.watch(categoriesProvider).valueOrNull ?? [];
    final pending = ref.watch(pendingSyncCountProvider).valueOrNull ?? 0;
    final sync = ref.watch(syncControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(children: [
        const _Header('Umum'),
        ListTile(
          title: const Text('Mata uang'),
          trailing: DropdownButton<String>(
            value: settings.currencyCode,
            items: [for (final e in kCurrencies.entries) DropdownMenuItem(value: e.key, child: Text('${e.key} (${e.value})'))],
            onChanged: (v) => notifier.update(settings.copyWith(currencyCode: v)),
          ),
        ),
        ListTile(
          title: const Text('Format tanggal'),
          trailing: DropdownButton<String>(
            value: settings.dateFormat,
            items: [for (final f in kDateFormats) DropdownMenuItem(value: f, child: Text(f))],
            onChanged: (v) => notifier.update(settings.copyWith(dateFormat: v)),
          ),
        ),
        const _Header('Kategori'),
        for (final c in categories)
          ListTile(
            leading: CircleAvatar(backgroundColor: Color(c.colorValue), radius: 8),
            title: Text(c.name),
            subtitle: c.keywords.isEmpty ? null : Text(c.keywords.join(', '), maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _editCategory(c),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await ref.read(categoryRepoProvider).delete(c.id);
                ref.invalidate(categoriesProvider);
              },
            ),
          ),
        ListTile(leading: const Icon(Icons.add), title: const Text('Tambah kategori'), onTap: () => _editCategory()),
        const _Header('Google Sheets'),
        if (!_connected)
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Hubungkan Google Sheets'),
            subtitle: const Text('Login Google (OAuth 2.0). Tidak ada kunci rahasia di aplikasi.'),
            trailing: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
            onTap: _busy ? null : _connect,
          )
        else ...[
          ListTile(leading: const Icon(Icons.account_circle_outlined), title: Text(_email ?? 'Terhubung')),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: Text(settings.spreadsheetTitle ?? 'Belum memilih spreadsheet'),
            subtitle: Text('Tab: ${settings.sheetName}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy ? null : _chooseSpreadsheet,
          ),
          ListTile(
            leading: sync.running
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            title: Text(pending == 0 ? 'Semua tersinkron' : '$pending menunggu dikirim'),
            subtitle: sync.message == null ? null : Text(sync.message!),
            trailing: TextButton(
              onPressed: sync.running ? null : () => ref.read(syncControllerProvider.notifier).syncNow(),
              child: const Text('Sinkron'),
            ),
          ),
          if (sync.needsReauth)
            ListTile(
              leading: const Icon(Icons.warning_amber),
              title: const Text('Sesi Google berakhir'),
              trailing: TextButton(onPressed: _connect, child: const Text('Hubungkan ulang')),
            ),
          ListTile(
            leading: const Icon(Icons.link_off),
            title: const Text('Putuskan Google Sheets'),
            onTap: _disconnect,
          ),
        ],
        const _Header('Privasi'),
        const ListTile(
          leading: Icon(Icons.lock_outline),
          title: Text('Data tersimpan di perangkat ini'),
          subtitle: Text('OCR berjalan on-device. Data hanya dikirim ke Google bila Anda menghubungkan Sheets.'),
        ),
        const SizedBox(height: 32),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

class _SheetChoice {
  _SheetChoice(this.createNew, this.value);
  final bool createNew;
  final String value; // judul (baru) atau ID/URL (yang ada)
}

/// Dialog pilih spreadsheet tujuan: buat baru atau tempel URL/ID.
class _SheetDialog extends StatefulWidget {
  const _SheetDialog();
  @override
  State<_SheetDialog> createState() => _SheetDialogState();
}

class _SheetDialogState extends State<_SheetDialog> {
  bool _createNew = true;
  final _ctrl = TextEditingController(text: '$kAppName Pembukuan');
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _ctrl.text.trim();
    if (_createNew) {
      if (text.isEmpty) return setState(() => _error = 'Judul wajib diisi');
      Navigator.pop(context, _SheetChoice(true, text));
    } else {
      final id = GoogleSheetsService.extractId(text);
      if (id == null) return setState(() => _error = 'URL/ID spreadsheet tidak valid');
      Navigator.pop(context, _SheetChoice(false, id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Spreadsheet tujuan'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Buat baru')),
            ButtonSegment(value: false, label: Text('Pakai yang ada')),
          ],
          selected: {_createNew},
          onSelectionChanged: (s) => setState(() {
            _createNew = s.first;
            _error = null;
            _ctrl.text = _createNew ? '$kAppName Pembukuan' : '';
          }),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ctrl,
          decoration: InputDecoration(
            labelText: _createNew ? 'Judul spreadsheet' : 'URL atau ID spreadsheet',
            errorText: _error,
          ),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(onPressed: _submit, child: const Text('Lanjut')),
      ],
    );
  }
}
