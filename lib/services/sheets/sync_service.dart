import 'dart:async';
import 'dart:io';

import 'package:googleapis/sheets/v4.dart' show DetailedApiRequestError;
import 'package:http/http.dart' as http;

import '../../data/repositories/sync_queue_repository.dart';
import '../../domain/models/app_settings.dart';
import 'google_auth_service.dart';
import 'google_sheets_service.dart';

enum SyncOutcome { success, nothingToDo, notConfigured, offline, authRequired, error }

class SyncReport {
  SyncReport(this.outcome, {this.sent = 0, this.message});
  final SyncOutcome outcome;
  final int sent;
  final String? message;
}

/// Mengirim antrean ke Google Sheets. Aman dipanggil berulang: ada mutex,
/// dan item hanya dihapus dari antrean setelah API menjawab sukses.
class SyncService {
  SyncService(this._queue, this._auth, this._sheets);

  final SyncQueueRepository _queue;
  final GoogleAuthService _auth;
  final GoogleSheetsService _sheets;
  bool _running = false;

  static const _batchSize = 100;

  Future<SyncReport> sync(AppSettings settings) async {
    if (!settings.hasSpreadsheet) return SyncReport(SyncOutcome.notConfigured);
    if (_running) return SyncReport(SyncOutcome.nothingToDo);
    _running = true;

    http.Client? client;
    var sent = 0;
    try {
      var batch = await _queue.pendingTransactions(limit: _batchSize);
      if (batch.isEmpty) return SyncReport(SyncOutcome.nothingToDo);

      client = await _auth.authenticatedClient();
      if (client == null) {
        return SyncReport(SyncOutcome.authRequired, message: 'Sesi Google berakhir. Hubungkan ulang.');
      }

      while (batch.isNotEmpty) {
        final ids = batch.map((t) => t.id).toList();
        try {
          await _sheets.append(client, settings.spreadsheetId!, settings.sheetName, batch);
        } on DetailedApiRequestError catch (e) {
          final msg = e.message ?? 'HTTP ${e.status}';
          await _queue.markFailed(ids, msg);
          final authProblem = e.status == 401 || e.status == 403;
          return SyncReport(authProblem ? SyncOutcome.authRequired : SyncOutcome.error,
              sent: sent, message: msg);
        }
        await _queue.markDone(ids);
        sent += ids.length;
        batch = await _queue.pendingTransactions(limit: _batchSize);
      }
      return SyncReport(SyncOutcome.success, sent: sent);
    } on SocketException {
      return SyncReport(SyncOutcome.offline, sent: sent);
    } on TimeoutException {
      return SyncReport(SyncOutcome.offline, sent: sent);
    } on http.ClientException {
      return SyncReport(SyncOutcome.offline, sent: sent);
    } catch (e) {
      return SyncReport(SyncOutcome.error, sent: sent, message: e.toString());
    } finally {
      client?.close();
      _running = false;
    }
  }
}
