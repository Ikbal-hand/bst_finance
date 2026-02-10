import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// Pastikan import model dan constants ini benar sesuai struktur project Anda
import '../../../core/constants/app_colors.dart';
import '../../../models/transaction_model.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  // --- STATE VARIABLES ---

  // Menggunakan DateTimeRange untuk rentang tanggal
  DateTimeRange _selectedDateRange = DateTimeRange(
    start: DateTime(DateTime.now().year, DateTime.now().month, 1), // Awal bulan ini
    end: DateTime.now(), // Hari ini
  );

  String? _selectedBranchId; // null = Semua/Pusat (untuk Owner)

  List<TransactionModel> _transactions = [];
  bool _isLoading = false;

  double _totalIncome = 0;
  double _totalExpense = 0;

  // User Info
  String _userRole = 'owner';
  String _currentUserId = '';

  @override
  void initState() {
    super.initState();
    _checkUserRole();
  }

  // 1. Cek Role User
  Future<void> _checkUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _currentUserId = user.uid;
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        if (mounted) {
          setState(() {
            _userRole = doc.data()?['role'] ?? 'admin_branch';
            // Jika bukan Owner, kunci filter cabang ke ID user sendiri
            if (_userRole != 'owner') {
              _selectedBranchId = doc.data()?['branch_id'] ?? 'bst_box';
            }
          });
        }
      }
      _fetchTransactions();
    }
  }

  // 2. Fetch Data (Support Range Tanggal)
  Future<void> _fetchTransactions() async {
    setState(() => _isLoading = true);

    // Set jam ke 00:00:00 untuk Start dan 23:59:59 untuk End
    DateTime start = DateTime(_selectedDateRange.start.year, _selectedDateRange.start.month, _selectedDateRange.start.day, 0, 0, 0);
    DateTime end = DateTime(_selectedDateRange.end.year, _selectedDateRange.end.month, _selectedDateRange.end.day, 23, 59, 59);

    try {
      Query query = FirebaseFirestore.instance
          .collection('transactions')
          .where('date', isGreaterThanOrEqualTo: start)
          .where('date', isLessThanOrEqualTo: end)
          .orderBy('date', descending: true);

      // Filter Cabang
      if (_selectedBranchId != null && _selectedBranchId != 'all') {
        query = query.where('related_branch_id', isEqualTo: _selectedBranchId);
      }

      final snapshot = await query.get();

      List<TransactionModel> loaded = [];
      double inc = 0;
      double exp = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        TransactionModel tx = TransactionModel.fromMap(data, doc.id);
        loaded.add(tx);

        if (tx.type == 'income') {
          inc += tx.amount;
        } else {
          exp += tx.amount;
        }
      }

      if (mounted) {
        setState(() {
          _transactions = loaded;
          _totalIncome = inc;
          _totalExpense = exp;
        });
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- PDF GENERATOR (LAYOUT KONSOLIDASI + GRAFIK PER CABANG) ---
  Future<void> _exportToPdf() async {
    // 1. SAFETY CHECK
    if (_transactions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tidak ada data untuk diekspor!"), backgroundColor: Colors.red));
      return;
    }

    final pdf = pw.Document();

    // Load Font
    final font = await PdfGoogleFonts.openSansRegular();
    final fontBold = await PdfGoogleFonts.openSansBold();

    // --- A. PERSIAPAN DATA GRAFIK GLOBAL ---
    final Map<int, double> globalDailyIncome = {};
    final Map<int, double> globalDailyExpense = {};

    // Hitung range hari
    int daysCount = _selectedDateRange.end.difference(_selectedDateRange.start).inDays + 1;

    // Init data harian dengan 0 untuk semua tanggal dalam range
    for (int i = 0; i < daysCount; i++) {
      DateTime d = _selectedDateRange.start.add(Duration(days: i));
      if (!globalDailyIncome.containsKey(d.day)) globalDailyIncome[d.day] = 0;
      if (!globalDailyExpense.containsKey(d.day)) globalDailyExpense[d.day] = 0;
    }

    // Isi Data Grafik Global
    for (var tx in _transactions) {
      int day = tx.date.day;
      if (tx.type == 'income') {
        globalDailyIncome[day] = (globalDailyIncome[day] ?? 0) + tx.amount;
      } else {
        globalDailyExpense[day] = (globalDailyExpense[day] ?? 0) + tx.amount;
      }
    }

    // Hitung MaxY & Ticks Global
    double globalMaxY = _calculateMaxY(globalDailyIncome, globalDailyExpense);
    List<int> globalYAxisTicks = _generateYAxisTicks(globalMaxY);

    // List X-Axis (Tanggal) untuk semua grafik
    List<int> xAxisTicks = globalDailyIncome.keys.toList()..sort();

    // Data Points Global
    final globalIncomePoints = globalDailyIncome.entries.map((e) => pw.PointChartValue(e.key.toDouble(), e.value)).toList();
    final globalExpensePoints = globalDailyExpense.entries.map((e) => pw.PointChartValue(e.key.toDouble(), e.value)).toList();

    // --- B. GROUPING DATA PER CABANG ---
    Map<String, List<TransactionModel>> groupedTx = {};

    if (_selectedBranchId == null || _selectedBranchId == 'all') {
      groupedTx = {
        'bst_box': [],
        'm_alfa': [],
        'saufa': [],
        'pusat': [],
      };
    } else {
      groupedTx = {_selectedBranchId!: []};
    }

    for (var tx in _transactions) {
      String key = tx.relatedBranchId ?? 'pusat';
      if (!groupedTx.containsKey(key)) {
        if (_selectedBranchId == null) groupedTx[key] = [];
        else continue;
      }
      groupedTx[key]!.add(tx);
    }

    String startFmt = DateFormat('dd MMM yyyy', 'id_ID').format(_selectedDateRange.start);
    String endFmt = DateFormat('dd MMM yyyy', 'id_ID').format(_selectedDateRange.end);
    String periodeStr = "$startFmt - $endFmt";

    // --- C. MEMBANGUN HALAMAN PDF ---
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(
          base: font,
          bold: fontBold,
        ),
        build: (pw.Context context) {
          return [
            // 1. JUDUL LAPORAN UTAMA
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("LAPORAN KEUANGAN KONSOLIDASI", style: pw.TextStyle(font: fontBold, fontSize: 18, color: PdfColors.blue900)),
                      pw.Text("BST FINANCE SYSTEM", style: pw.TextStyle(font: font, fontSize: 14, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text("Periode: $periodeStr", style: pw.TextStyle(font: font, fontSize: 10)),
                      pw.Text("Dicetak: ${DateFormat('dd MMM yyyy').format(DateTime.now())}", style: pw.TextStyle(font: font, fontSize: 10)),
                    ],
                  )
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // 2. RINGKASAN & GRAFIK GLOBAL
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // KIRI: KOTAK TOTAL
                pw.Expanded(
                  flex: 2,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("TOTAL KESELURUHAN", style: pw.TextStyle(font: fontBold, fontSize: 12)),
                        pw.Divider(),
                        pw.SizedBox(height: 8),
                        _buildSummaryRowPdf("Total Pemasukan", _totalIncome, PdfColors.green800, fontBold),
                        pw.SizedBox(height: 8),
                        _buildSummaryRowPdf("Total Pengeluaran", _totalExpense, PdfColors.red800, fontBold),
                        pw.Divider(),
                        _buildSummaryRowPdf("Laba Bersih", _totalIncome - _totalExpense, PdfColors.blue800, fontBold, isTotal: true),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 20),

                // KANAN: GRAFIK GLOBAL
                pw.Expanded(
                  flex: 3,
                  child: pw.Container(
                    height: 140,
                    child: pw.Chart(
                      title: pw.Text("Grafik Global (Harian)", style: pw.TextStyle(font: font, fontSize: 10)),
                      grid: pw.CartesianGrid(
                        xAxis: pw.FixedAxis(xAxisTicks, marginStart: 0, marginEnd: 0, divisions: true),
                        yAxis: pw.FixedAxis(globalYAxisTicks, divisions: true),
                      ),
                      datasets: [
                        pw.LineDataSet(
                          legend: 'Masuk', drawSurface: true, isCurved: true, drawPoints: false,
                          color: PdfColors.green, surfaceColor: PdfColors.green100, data: globalIncomePoints,
                        ),
                        pw.LineDataSet(
                          legend: 'Keluar', drawSurface: true, isCurved: true, drawPoints: false,
                          color: PdfColors.red, surfaceColor: PdfColors.red100, data: globalExpensePoints,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 20),
            pw.Divider(thickness: 2, color: PdfColors.grey200),
            pw.SizedBox(height: 10),

            // 3. LOOPING CABANG (DENGAN GRAFIK PER CABANG)
            ...groupedTx.entries.expand((entry) {
              String branchKey = entry.key;
              List<TransactionModel> txList = entry.value;

              if (txList.isEmpty) return [pw.SizedBox()];

              // A. HITUNG SUBTOTAL CABANG
              double subIncome = 0;
              double subExpense = 0;

              // B. PERSIAPAN DATA GRAFIK CABANG
              final Map<int, double> branchIncome = {};
              final Map<int, double> branchExpense = {};

              // Init 0 untuk range tanggal (agar grafik x-axis sama dengan global)
              for (int i = 0; i < daysCount; i++) {
                DateTime d = _selectedDateRange.start.add(Duration(days: i));
                if (!branchIncome.containsKey(d.day)) branchIncome[d.day] = 0;
                if (!branchExpense.containsKey(d.day)) branchExpense[d.day] = 0;
              }

              for (var t in txList) {
                if (t.type == 'income') {
                  subIncome += t.amount;
                  branchIncome[t.date.day] = (branchIncome[t.date.day] ?? 0) + t.amount;
                } else {
                  subExpense += t.amount;
                  branchExpense[t.date.day] = (branchExpense[t.date.day] ?? 0) + t.amount;
                }
              }

              // Hitung Skala Y Khusus Cabang Ini
              double branchMaxY = _calculateMaxY(branchIncome, branchExpense);
              List<int> branchYAxisTicks = _generateYAxisTicks(branchMaxY);

              // Data Points Cabang
              final branchIncomePoints = branchIncome.entries.map((e) => pw.PointChartValue(e.key.toDouble(), e.value)).toList();
              final branchExpensePoints = branchExpense.entries.map((e) => pw.PointChartValue(e.key.toDouble(), e.value)).toList();

              // Judul & Style
              String branchTitleName = _getBranchName(branchKey).toUpperCase();
              String subTitle = "";

              if (branchKey == 'pusat') {
                branchTitleName = "BENDAHARA PUSAT";
                subTitle = "(Rincian Penggunaan Dana Perusahaan)";
              } else {
                branchTitleName = "CABANG: $branchTitleName";
              }

              return [
                pw.SizedBox(height: 20),

                // HEADER CABANG
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  color: branchKey == 'pusat' ? PdfColors.orange100 : PdfColors.blue50,
                  width: double.infinity,
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(branchTitleName, style: pw.TextStyle(font: fontBold, fontSize: 12)),
                            if(subTitle.isNotEmpty)
                              pw.Text(subTitle, style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700)),
                          ]
                      ),
                      pw.Row(
                          children: [
                            _buildMiniTag("Masuk", subIncome, PdfColors.green, font),
                            pw.SizedBox(width: 8),
                            _buildMiniTag("Keluar", subExpense, PdfColors.red, font),
                            pw.SizedBox(width: 8),
                            _buildMiniTag("Net", subIncome - subExpense, PdfColors.blue, fontBold),
                          ]
                      )
                    ],
                  ),
                ),
                pw.SizedBox(height: 10),

                // [NEW] GRAFIK CABANG
                pw.Container(
                  height: 100, // Tinggi lebih kecil sedikit dari global
                  child: pw.Chart(
                    title: pw.Text("Grafik Harian ($branchTitleName)", style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600)),
                    grid: pw.CartesianGrid(
                      xAxis: pw.FixedAxis(xAxisTicks, marginStart: 0, marginEnd: 0, divisions: true),
                      yAxis: pw.FixedAxis(branchYAxisTicks, divisions: true), // Skala dinamis per cabang
                    ),
                    datasets: [
                      pw.LineDataSet(
                        legend: 'Masuk', drawSurface: true, isCurved: true, drawPoints: false,
                        color: PdfColors.green, surfaceColor: PdfColors.green50, data: branchIncomePoints,
                      ),
                      pw.LineDataSet(
                        legend: 'Keluar', drawSurface: true, isCurved: true, drawPoints: false,
                        color: PdfColors.red, surfaceColor: PdfColors.red50, data: branchExpensePoints,
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 10),

                // TABEL TRANSAKSI CABANG
                pw.TableHelper.fromTextArray(
                  headers: ['Tgl', 'Kategori', 'Keterangan', 'Masuk', 'Keluar'],
                  headerStyle: pw.TextStyle(font: fontBold, color: PdfColors.white, fontSize: 9),
                  headerDecoration: pw.BoxDecoration(color: branchKey == 'pusat' ? PdfColors.orange800 : PdfColors.blue800),
                  rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
                  cellAlignment: pw.Alignment.centerLeft,
                  cellAlignments: {
                    3: pw.Alignment.centerRight,
                    4: pw.Alignment.centerRight
                  },
                  data: txList.map((tx) {
                    final isIncome = tx.type == 'income';
                    return [
                      DateFormat('dd MMM').format(tx.date),
                      tx.category,
                      tx.description,
                      isIncome ? _formatRupiah(tx.amount) : '-',
                      !isIncome ? _formatRupiah(tx.amount) : '-',
                    ];
                  }).toList(),
                  cellStyle: pw.TextStyle(font: font, fontSize: 9),
                ),
              ];
            }).toList(),
          ];
        },
      ),
    );

    // DIRECT SHARE
    final String fileName = 'Laporan_Keuangan_BST_${DateFormat('dd_MMM').format(_selectedDateRange.start)}_sd_${DateFormat('dd_MMM_yyyy').format(_selectedDateRange.end)}.pdf';

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: fileName,
    );
  }

  // --- HELPER LOGIC UNTUK GRAFIK ---

  // Menghitung Nilai Tertinggi (Max Y) dari kumpulan data
  double _calculateMaxY(Map<int, double> incomeMap, Map<int, double> expenseMap) {
    double max = 0;
    for (var val in incomeMap.values) if (val > max) max = val;
    for (var val in expenseMap.values) if (val > max) max = val;
    if (max == 0) max = 1000000;
    return max * 1.1; // Buffer 10%
  }

  // Membuat Ticks untuk Sumbu Y (0, 25%, 50%, 75%, 100%)
  List<int> _generateYAxisTicks(double maxY) {
    return [
      0,
      (maxY * 0.25).toInt(),
      (maxY * 0.50).toInt(),
      (maxY * 0.75).toInt(),
      maxY.toInt()
    ];
  }

  // --- HELPER WIDGETS UI ---

  pw.Widget _buildSummaryRowPdf(String label, double value, PdfColor color, pw.Font font, {bool isTotal = false}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey800)),
        pw.Text(
          _formatRupiah(value),
          style: pw.TextStyle(font: font, fontSize: isTotal ? 12 : 10, color: color),
        ),
      ],
    );
  }

  pw.Widget _buildMiniTag(String label, double value, PdfColor color, pw.Font font) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        pw.Text(_formatRupiah(value), style: pw.TextStyle(font: font, fontSize: 9, color: color)),
      ],
    );
  }

  String _formatRupiah(double number) {
    return NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(number);
  }

  String _getBranchName(String? branchId) {
    if (branchId == null) return 'Semua Cabang';
    switch (branchId) {
      case 'bst_box': return 'Box Factory';
      case 'm_alfa': return 'Maint. Alfa';
      case 'saufa': return 'Saufa Olshop';
      case 'pusat': return 'Kantor Pusat';
      default: return 'Cabang Lain';
    }
  }

  Future<void> _pickDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            primaryColor: AppColors.primary,
            colorScheme: const ColorScheme.light(primary: AppColors.primary),
            buttonTheme: const ButtonThemeData(textTheme: ButtonTextTheme.primary),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _selectedDateRange = picked);
      _fetchTransactions();
    }
  }

  // --- UI BUILD ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Laporan Keuangan", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.blue),
            tooltip: "Bagikan PDF Laporan",
            onPressed: _transactions.isEmpty ? null : _exportToPdf,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickDateRange,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          const Icon(Icons.date_range, size: 16, color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "${DateFormat('dd MMM').format(_selectedDateRange.start)} - ${DateFormat('dd MMM yyyy').format(_selectedDateRange.end)}",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                if (_userRole == 'owner')
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedBranchId,
                          isExpanded: true,
                          hint: const Text("Semua"),
                          items: const [
                            DropdownMenuItem(value: null, child: Text("Semua / Pusat")),
                            DropdownMenuItem(value: 'bst_box', child: Text("Box Factory")),
                            DropdownMenuItem(value: 'm_alfa', child: Text("Maint. Alfa")),
                            DropdownMenuItem(value: 'saufa', child: Text("Saufa Olshop")),
                          ],
                          onChanged: (val) {
                            setState(() => _selectedBranchId = val);
                            _fetchTransactions();
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(child: _buildSummaryCard("Masuk", _totalIncome, Colors.green)),
                const SizedBox(width: 10),
                Expanded(child: _buildSummaryCard("Keluar", _totalExpense, Colors.red)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildSummaryCard("Selisih (Net)", _totalIncome - _totalExpense, Colors.blue, isFullWidth: true),
          ),

          const SizedBox(height: 10),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _transactions.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.insert_chart_outlined, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 10),
                  const Text("Tidak ada data laporan", style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
                : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _transactions.length,
              separatorBuilder: (c, i) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final tx = _transactions[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: tx.type == 'income' ? Colors.green[50] : Colors.red[50],
                    child: Icon(
                      tx.type == 'income' ? Icons.arrow_downward : Icons.arrow_upward,
                      color: tx.type == 'income' ? Colors.green : Colors.red,
                      size: 20,
                    ),
                  ),
                  title: Text(tx.category, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${DateFormat('dd MMM').format(tx.date)} • ${tx.description}", maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Text(
                    _formatRupiah(tx.amount),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: tx.type == 'income' ? Colors.green : Colors.red,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, double amount, Color color, {bool isFullWidth = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3))),
      child: Column(
        crossAxisAlignment: isFullWidth ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            NumberFormat.compactCurrency(locale: 'id_ID', symbol: 'Rp ').format(amount),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}