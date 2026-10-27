import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/permissions.dart';
import '../providers.dart';
import 'review_screen.dart';

enum _Step { idle, cropping, recognizing }

/// Alur: pilih sumber -> crop -> kompres -> OCR -> parse -> buka form Review.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  _Step _step = _Step.idle;
  String? _error;

  Future<void> _start(ImageSource source) async {
    setState(() => _error = null);
    final ocr = ref.read(ocrServiceProvider);

    try {
      if (source == ImageSource.camera && !await _cameraAllowed()) return;

      final picked = await ocr.pick(source);
      if (picked == null) return; // dibatalkan

      setState(() => _step = _Step.cropping);
      final cropped = await ocr.crop(picked);
      if (cropped == null) {
        setState(() => _step = _Step.idle);
        return;
      }

      setState(() => _step = _Step.recognizing);
      final parser = await ref.read(receiptParserProvider.future);
      final result = await ocr.process(cropped, parser);

      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ReviewScreen(parsed: result.parsed, imagePath: result.imagePath)),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal memproses gambar: $e');
    } finally {
      if (mounted && _step != _Step.idle) setState(() => _step = _Step.idle);
    }
  }

  Future<bool> _cameraAllowed() async {
    final r = await PermissionHelper.ensureCamera();
    if (r == PermissionResult.granted) return true;
    if (!mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Izin kamera dibutuhkan'),
        content: Text(r == PermissionResult.permanentlyDenied
            ? 'Izin kamera ditolak permanen. Aktifkan di Pengaturan sistem, atau pilih foto dari galeri.'
            : 'Aplikasi memakai kamera hanya untuk memotret struk. Anda juga bisa memilih dari galeri.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
          if (r == PermissionResult.permanentlyDenied)
            FilledButton(
              onPressed: () {
                PermissionHelper.openSettings();
                Navigator.pop(ctx);
              },
              child: const Text('Buka Pengaturan'),
            ),
        ],
      ),
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final busy = _step != _Step.idle;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan struk')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: busy
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_step == _Step.cropping ? 'Memotong gambar…' : 'Membaca teks struk…'),
                ])
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.receipt_long, size: 72),
                  const SizedBox(height: 12),
                  const Text('Foto struk di tempat terang dan rata agar hasil OCR akurat.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _start(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera),
                      label: const Text('Ambil foto'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _start(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Pilih dari galeri'),
                    ),
                  ),
                ]),
        ),
      ),
    );
  }
}
