/// Konstanta global aplikasi.
const kAppName = 'CatatNota'; // GANTI dengan nama aplikasi Anda.

/// Nama channel untuk Apple Vision OCR (harus sama dengan di VisionOcr.swift).
const kVisionChannel = 'catatnota/vision_ocr';

/// Urutan kolom di Excel dan Google Sheets.
const kExportHeaders = <String>[
  'Tanggal',
  'Merchant',
  'Deskripsi',
  'Kategori',
  'Subtotal',
  'Pajak',
  'Total',
  'Catatan',
];

const kDefaultSheetName = 'Transaksi';

/// Mata uang yang tidak memakai desimal.
const kZeroDecimalCurrencies = {'IDR', 'JPY', 'KRW', 'VND'};

const kCurrencies = <String, String>{
  'IDR': 'Rp',
  'USD': r'$',
  'EUR': '€',
  'SGD': r'S$',
  'MYR': 'RM',
  'JPY': '¥',
};

const kDateFormats = <String>['dd/MM/yyyy', 'dd-MM-yyyy', 'yyyy-MM-dd', 'd MMM yyyy'];

const kPaymentMethods = <String>[
  'Tunai', 'QRIS', 'Debit', 'Kredit', 'Transfer', 'GoPay', 'OVO', 'DANA', 'ShopeePay', 'LinkAja',
];
