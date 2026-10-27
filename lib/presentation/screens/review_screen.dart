import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../domain/models/parsed_receipt.dart';
import '../../domain/models/transaction.dart';
import '../../services/parser/receipt_parser.dart';
import '../providers.dart';

/// Form validasi/edit. Dipakai untuk 3 kasus:
///  - hasil scan  : `parsed` + `imagePath`
///  - edit        : `existing`
///  - input manual: tanpa argumen
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, this.parsed, this.imagePath, this.existing});

  final ParsedReceipt? parsed;
  final String? imagePath;
  final Transaction? existing;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _date;
  late final TextEditingController _merchant, _description, _subtotal, _tax, _total, _notes;
  String? _category;
  String? _payment;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final p = widget.parsed;
    _date = e?.date ?? p?.date ?? DateTime.now();
    _merchant = TextEditingController(text: e?.merchant ?? p?.merchant ?? '');
    _description = TextEditingController(text: e?.description ?? p?.description ?? '');
    _subtotal = TextEditingController(text: _num(e?.subtotal ?? p?.subtotal));
    _tax = TextEditingController(text: _num(e?.tax ?? p?.tax));
    _total = TextEditingController(text: _num(e?.total ?? p?.total));
    _notes = TextEditingController(text: e?.notes ?? '');
    _category = e?.category ?? p?.category;
    _payment = e?.paymentMethod ?? p?.paymentMethod;
  }

  @override
  void dispose() {
    for (final c in [_merchant, _description, _subtotal, _tax, _total, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String _num(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString());

  double _val(TextEditingController c) => parseAmount(c.text) ?? 0;

  String? _validateAmount(String? v, {bool required = false}) {
    if (v == null || v.trim().isEmpty) return required ? 'Wajib diisi' : null;
    final n = parseAmount(v);
    if (n == null) return 'Angka tidak valid';
    if (n < 0) return 'Tidak boleh negatif';
    return null;
  }

  /// Peringatan lunak (bukan error) bila subtotal + pajak ≠ total.
  String? get _mismatchWarning {
    final sub = _val(_subtotal), tax = _val(_tax), total = _val(_total);
    if (sub == 0 && tax == 0) return null;
    return (sub + tax - total).abs() > 1 ? 'Subtotal + pajak ≠ total. Periksa kembali angka.' : null;
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final actions = ref.read(transactionActionsProvider);
    try {
      final total = _val(_total);
      var subtotal = _val(_subtotal);
      final tax = _val(_tax);
      if (subtotal == 0) subtotal = total - tax; // lengkapi otomatis bila kosong

      if (_isEdit) {
        await actions.update(widget.existing!.copyWith(
          date: _date,
          merchant: _merchant.text.trim(),
          description: _description.text.trim(),
          category: _category ?? 'Lainnya',
          subtotal: subtotal,
          tax: tax,
          total: total,
          paymentMethod: _payment,
          notes: _notes.text.trim(),
        ));
      } else {
        var t = actions.newTransaction(
          date: _date,
          merchant: _merchant.text.trim(),
          description: _description.text.trim(),
          category: _category ?? 'Lainnya',
          subtotal: subtotal,
          tax: tax,
          total: total,
          paymentMethod: _payment,
          notes: _notes.text.trim(),
          rawText: widget.parsed?.rawText,
        );
        if (widget.imagePath != null) {
          final saved = await ref.read(ocrServiceProvider).preprocessor.persist(widget.imagePath!, t.id);
          t = t.copyWith(imagePath: saved);
        }
        await actions.create(t);
      }
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isEdit ? 'Perubahan disimpan' : 'Transaksi disimpan')));
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyimpan: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final categories = ref.watch(categoriesProvider).valueOrNull ?? [];
    final imagePath = widget.imagePath ?? widget.existing?.imagePath;
    final raw = widget.parsed?.rawText ?? widget.existing?.rawText;
    final names = categories.map((c) => c.name).toList();
    if (_category != null && !names.contains(_category)) names.add(_category!); // kategori lama yang sudah dihapus

    final amountFormatters = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    final warn = _mismatchWarning;

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit transaksi' : 'Periksa data')),
      body: Form(
        key: _formKey,
        onChanged: () => setState(() {}), // perbarui peringatan
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (imagePath != null && File(imagePath).existsSync())
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(imagePath), height: 180, fit: BoxFit.cover),
              ),
            if (widget.parsed != null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Hasil OCR bisa salah baca. Periksa tiap kolom sebelum menyimpan.',
                    style: TextStyle(fontStyle: FontStyle.italic)),
              ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Tanggal', border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today)),
                child: Text(Fmt.date(_date, settings)),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _merchant,
              decoration: const InputDecoration(labelText: 'Merchant / toko', border: OutlineInputBorder()),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Deskripsi', border: OutlineInputBorder()),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: names.contains(_category) ? _category : null,
              decoration: const InputDecoration(labelText: 'Kategori', border: OutlineInputBorder()),
              items: [for (final n in names) DropdownMenuItem(value: n, child: Text(n))],
              onChanged: (v) => setState(() => _category = v),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _subtotal,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: amountFormatters,
                  decoration: InputDecoration(labelText: 'Subtotal', prefixText: '${settings.currencySymbol} ', border: const OutlineInputBorder()),
                  validator: _validateAmount,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _tax,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: amountFormatters,
                  decoration: InputDecoration(labelText: 'Pajak', prefixText: '${settings.currencySymbol} ', border: const OutlineInputBorder()),
                  validator: _validateAmount,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: _total,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: amountFormatters,
              decoration: InputDecoration(
                labelText: 'Total',
                prefixText: '${settings.currencySymbol} ',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Hitung dari subtotal + pajak',
                  icon: const Icon(Icons.calculate_outlined),
                  onPressed: () => setState(() => _total.text = _num(_val(_subtotal) + _val(_tax))),
                ),
              ),
              validator: (v) => _validateAmount(v, required: true),
            ),
            if (warn != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(warn, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: kPaymentMethods.contains(_payment) ? _payment : null,
              decoration: const InputDecoration(labelText: 'Metode pembayaran (opsional)', border: OutlineInputBorder()),
              items: [for (final m in kPaymentMethods) DropdownMenuItem(value: m, child: Text(m))],
              onChanged: (v) => setState(() => _payment = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Catatan', border: OutlineInputBorder()),
              maxLines: 2,
            ),
            if (raw != null && raw.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Teks OCR mentah'),
                children: [SelectableText(raw, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))],
              ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(_isEdit ? 'Simpan perubahan' : 'Simpan transaksi'),
            ),
          ],
        ),
      ),
    );
  }
}
