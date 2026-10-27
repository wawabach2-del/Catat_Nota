import 'dart:io';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants.dart';
import '../../domain/models/transaction.dart';

/// Membuat file .xlsx baru atau menambahkan baris ke file .xlsx yang ada.
///
/// Keterbatasan penting:
/// * Mobile OS tidak mengizinkan menulis balik ke file yang dipilih lewat
///   file picker, jadi hasil SELALU berupa file baru di folder aplikasi
///   (salinan file lama + baris baru), lalu dibagikan lewat share sheet.
/// * Paket `excel` bisa kehilangan fitur Excel tingkat lanjut (chart, pivot,
///   sebagian conditional formatting) pada file yang dibuat di Excel desktop.
class ExcelExportService {
  Future<File> export(List<Transaction> items, {File? appendTo, String sheetName = kDefaultSheetName}) async {
    final Excel excel;
    if (appendTo != null) {
      excel = Excel.decodeBytes(await appendTo.readAsBytes());
    } else {
      excel = Excel.createExcel();
      final def = excel.getDefaultSheet();
      if (def != null && def != sheetName) excel.rename(def, sheetName);
    }

    final sheet = excel[sheetName]; // dibuat otomatis bila belum ada
    if (sheet.maxRows == 0) {
      sheet.appendRow(kExportHeaders.map<CellValue>((h) => TextCellValue(h)).toList());
      final headerStyle = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('#E0E0E0'));
      for (var c = 0; c < kExportHeaders.length; c++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).cellStyle = headerStyle;
      }
    }

    final dateStyle = CellStyle(numberFormat: NumFormat.custom(formatCode: 'yyyy-mm-dd'));
    final moneyStyle = CellStyle(numberFormat: NumFormat.custom(formatCode: '#,##0.00'));

    for (final t in items) {
      sheet.appendRow(<CellValue>[
        DateCellValue(year: t.date.year, month: t.date.month, day: t.date.day),
        TextCellValue(t.merchant),
        TextCellValue(t.description),
        TextCellValue(t.category),
        DoubleCellValue(t.subtotal),
        DoubleCellValue(t.tax),
        DoubleCellValue(t.total),
        TextCellValue(t.notes),
      ]);
      // Terapkan format ke baris yang baru ditambahkan.
      final r = sheet.maxRows - 1;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).cellStyle = dateStyle;
      for (final c in [4, 5, 6]) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).cellStyle = moneyStyle;
      }
    }

    final bytes = excel.encode();
    if (bytes == null) throw const FileSystemException('Gagal membuat file Excel');

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'exports'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final name = 'pembukuan_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
    return File(p.join(dir.path, name)).writeAsBytes(bytes, flush: true);
  }
}
