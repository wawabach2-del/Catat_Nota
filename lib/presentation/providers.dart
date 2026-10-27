import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../data/repositories/category_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/sync_queue_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../domain/models/app_settings.dart';
import '../domain/models/category.dart';
import '../domain/models/transaction.dart';
import '../services/export/excel_export_service.dart';
import '../services/ocr/ocr_service.dart';
import '../services/parser/receipt_parser.dart';
import '../services/sheets/google_auth_service.dart';
import '../services/sheets/google_sheets_service.dart';
import '../services/sheets/sync_service.dart';

// ───────────── Infrastruktur (di-override di main.dart) ─────────────
final databaseProvider = Provider<Database>((_) => throw UnimplementedError('override di main()'));
final sharedPrefsProvider = Provider<SharedPreferences>((_) => throw UnimplementedError('override di main()'));

// ───────────── Repository & service ─────────────
final transactionRepoProvider = Provider((ref) => TransactionRepository(ref.watch(databaseProvider)));
final categoryRepoProvider = Provider((ref) => CategoryRepository(ref.watch(databaseProvider)));
final syncQueueRepoProvider = Provider((ref) => SyncQueueRepository(ref.watch(databaseProvider)));
final settingsRepoProvider = Provider((ref) => SettingsRepository(ref.watch(sharedPrefsProvider)));

final ocrServiceProvider = Provider((_) => OcrService());
final excelServiceProvider = Provider((_) => ExcelExportService());
final googleAuthProvider = Provider((_) => GoogleAuthService());
final sheetsServiceProvider = Provider((_) => GoogleSheetsService());
final syncServiceProvider = Provider((ref) => SyncService(
      ref.watch(syncQueueRepoProvider),
      ref.watch(googleAuthProvider),
      ref.watch(sheetsServiceProvider),
    ));

// ───────────── Pengaturan ─────────────
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(settingsRepoProvider).load();

  Future<void> update(AppSettings s) async {
    state = s;
    await ref.read(settingsRepoProvider).save(s);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

// ───────────── Kategori ─────────────
final categoriesProvider = FutureProvider<List<Category>>((ref) => ref.watch(categoryRepoProvider).all());

// ───────────── Riwayat ─────────────
final historyFilterProvider = StateProvider<TransactionFilter>((_) => const TransactionFilter());

final transactionsProvider = FutureProvider.autoDispose<List<Transaction>>(
  (ref) => ref.watch(transactionRepoProvider).query(ref.watch(historyFilterProvider)),
);

class HomeSummary {
  HomeSummary(this.monthTotal, this.monthCount, this.recent);
  final double monthTotal;
  final int monthCount;
  final List<Transaction> recent;
}

final homeSummaryProvider = FutureProvider.autoDispose<HomeSummary>((ref) async {
  final repo = ref.watch(transactionRepoProvider);
  final now = DateTime.now();
  final s = await repo.summary(DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 0));
  final recent = await repo.query(const TransactionFilter(), limit: 5);
  return HomeSummary(s.total, s.count, recent);
});

final pendingSyncCountProvider =
    FutureProvider.autoDispose<int>((ref) => ref.watch(syncQueueRepoProvider).pendingCount());

// ───────────── Aksi transaksi (CRUD + efek sampingnya) ─────────────
class TransactionActions {
  TransactionActions(this._ref);
  final Ref _ref;

  Transaction newTransaction({
    required DateTime date,
    required String merchant,
    String description = '',
    String category = 'Lainnya',
    double subtotal = 0,
    double tax = 0,
    required double total,
    String? paymentMethod,
    String notes = '',
    String? imagePath,
    String? rawText,
  }) {
    final now = DateTime.now();
    return Transaction(
      id: const Uuid().v4(),
      date: date,
      merchant: merchant,
      description: description,
      category: category,
      subtotal: subtotal,
      tax: tax,
      total: total,
      paymentMethod: paymentMethod,
      notes: notes,
      imagePath: imagePath,
      rawText: rawText,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Simpan lokal DULU (selalu berhasil tanpa internet), lalu coba sync di latar belakang.
  Future<void> create(Transaction t) async {
    final settings = _ref.read(settingsProvider);
    await _ref.read(transactionRepoProvider).insert(t, enqueueForSync: settings.hasSpreadsheet);
    _refresh();
    unawaited(_ref.read(syncControllerProvider.notifier).syncNow());
  }

  Future<void> update(Transaction t) async {
    await _ref.read(transactionRepoProvider).update(t);
    _refresh();
  }

  Future<void> delete(String id) async {
    await _ref.read(transactionRepoProvider).delete(id);
    _refresh();
  }

  void _refresh() {
    _ref.invalidate(transactionsProvider);
    _ref.invalidate(homeSummaryProvider);
    _ref.invalidate(pendingSyncCountProvider);
  }
}

final transactionActionsProvider = Provider((ref) => TransactionActions(ref));

/// Parser dibangun dari kategori + kata kuncinya yang sekarang.
final receiptParserProvider = FutureProvider<ReceiptParser>((ref) async {
  final cats = await ref.watch(categoriesProvider.future);
  return ReceiptParser(categoryKeywords: {for (final c in cats) c.name: c.keywords});
});

// ───────────── Sinkronisasi ─────────────
class SyncUiState {
  const SyncUiState({this.running = false, this.message, this.needsReauth = false, this.lastSync});
  final bool running;
  final String? message;
  final bool needsReauth;
  final DateTime? lastSync;
}

class SyncController extends Notifier<SyncUiState> {
  StreamSubscription<List<ConnectivityResult>>? _sub;

  @override
  SyncUiState build() {
    // Sinkron otomatis begitu koneksi kembali.
    _sub = Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none)) syncNow();
    });
    ref.onDispose(() => _sub?.cancel());
    Future.microtask(syncNow); // coba sekali saat aplikasi dibuka
    return const SyncUiState();
  }

  Future<SyncReport> syncNow() async {
    final settings = ref.read(settingsProvider);
    if (!settings.hasSpreadsheet) return SyncReport(SyncOutcome.notConfigured);
    state = const SyncUiState(running: true);
    final report = await ref.read(syncServiceProvider).sync(settings);
    state = SyncUiState(
      message: switch (report.outcome) {
        SyncOutcome.success => '${report.sent} transaksi terkirim',
        SyncOutcome.offline => 'Offline — akan dicoba lagi otomatis',
        SyncOutcome.authRequired => report.message,
        SyncOutcome.error => report.message,
        _ => null,
      },
      needsReauth: report.outcome == SyncOutcome.authRequired,
      lastSync: report.outcome == SyncOutcome.success ? DateTime.now() : state.lastSync,
    );
    ref.invalidate(pendingSyncCountProvider);
    ref.invalidate(transactionsProvider);
    return report;
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncUiState>(SyncController.new);
