import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/transaction_model.dart';
import '../../transactions/presentation/add_transaction_screen.dart';
import '../../transactions/data/transaction_repository.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  // Filter State
  String _selectedType = 'all';
  String _selectedBranchFilter = 'all'; // Khusus Owner
  DateTime? _startDate;
  DateTime? _endDate;

  // User Data
  String _userRole = 'admin_branch';
  String _userBranchId = '';
  bool _isLoadingUser = true;

  @override
  void initState() {
    super.initState();
    _initUser();
  }

  void _initUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && mounted) {
        setState(() {
          _userRole = doc['role'] ?? 'admin_branch';
          _userBranchId = doc['branch_id'] ?? 'bst_box';
          _isLoadingUser = false;
        });
      }
    }
  }

  // [LOGIC INTI] Query Builder yang Strict
  Query _buildQuery() {
    Query query = FirebaseFirestore.instance.collection('transactions')
        .where('deleted_at', isNull: true); // Hanya data aktif

    // 1. Filter Cabang (Role Based)
    if (_userRole == 'owner') {
      // Owner bisa pilih cabang. Jika 'all', ambil semua.
      if (_selectedBranchFilter != 'all') {
        query = query.where('related_branch_id', isEqualTo: _selectedBranchFilter);
      }
    } else {
      // Admin Cabang DIPAKSA hanya melihat cabangnya sendiri
      query = query.where('related_branch_id', isEqualTo: _userBranchId);
    }

    // 2. Filter Tipe (Income/Expense)
    if (_selectedType != 'all') {
      query = query.where('type', isEqualTo: _selectedType);
    }

    // 3. Filter Tanggal
    // Note: Firestore butuh Composite Index jika filter range + equality dicampur.
    // Jika muncul error link di debug console, klik link tersebut.
    if (_startDate != null && _endDate != null) {
      DateTime start = DateTime(_startDate!.year, _startDate!.month, _startDate!.day, 0, 0, 0);
      DateTime end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
      query = query.where('date', isGreaterThanOrEqualTo: start).where('date', isLessThanOrEqualTo: end);
    }

    // Sorting terakhir
    return query.orderBy('date', descending: true);
  }

  Future<void> _deleteTransaction(TransactionModel tx) async {
    bool confirm = await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text("Hapus Transaksi?"),
          content: const Text("Saldo akan dikembalikan dan transaksi masuk Sampah."),
          actions: [
            TextButton(onPressed: ()=>Navigator.pop(c,false), child: const Text("Batal")),
            TextButton(onPressed: ()=>Navigator.pop(c,true), child: const Text("Hapus", style: TextStyle(color: Colors.red))),
          ],
        )
    ) ?? false;

    if (confirm) {
      await TransactionRepository().deleteTransaction(tx);
      if(mounted) setState((){}); // Refresh UI
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingUser) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("Riwayat Transaksi", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(icon: const Icon(Icons.filter_list), onPressed: _showFilterDialog)
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _buildQuery().snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return const Center(child: Text("Belum ada data sesuai filter."));

          // Hitung Summary (Exclude Mutasi Internal)
          double totalIncome = 0;
          double totalExpense = 0;

          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            double amount = (data['amount'] ?? 0).toDouble();
            String type = data['type'];
            String category = (data['category'] ?? '').toString().toLowerCase();

            // Mutasi/TopUp tidak dihitung di summary Pemasukan/Pengeluaran
            bool isTransfer = category.contains('mutasi') || category.contains('top up') || category.contains('suntikan');

            if (!isTransfer) {
              if (type == 'income') totalIncome += amount; else totalExpense += amount;
            }
          }

          return Column(
            children: [
              _buildSummaryHeader(totalIncome, totalExpense),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (c, i) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final tx = TransactionModel.fromMap(data, docs[index].id);
                    return _buildTransactionCard(tx);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryHeader(double income, double expense) {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(child: _summaryItem("Pemasukan", income, AppColors.success)),
          Container(width: 1, height: 40, color: Colors.grey[300]),
          Expanded(child: _summaryItem("Pengeluaran", expense, AppColors.error)),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, double value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(value),
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }

  Widget _buildTransactionCard(TransactionModel tx) {
    bool isIncome = tx.type == 'income';
    bool isTransfer = tx.category.toLowerCase().contains('mutasi') || tx.category.toLowerCase().contains('top up') || tx.category.toLowerCase().contains('suntikan');

    // Logic permission edit/delete
    bool allowEdit = !tx.category.toLowerCase().contains('utang') && !tx.category.toLowerCase().contains('approval');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Row(
        children: [
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: isTransfer ? Colors.blue[50] : (isIncome ? Colors.green[50] : Colors.red[50]), shape: BoxShape.circle),
              child: Icon(isTransfer ? Icons.swap_horiz : (isIncome ? Icons.arrow_downward : Icons.arrow_upward), color: isTransfer ? Colors.blue : (isIncome ? Colors.green : Colors.red), size: 20)
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tx.category, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            Text(tx.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            Text(DateFormat('dd MMM yyyy, HH:mm').format(tx.date), style: TextStyle(color: Colors.grey[400], fontSize: 10))
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text("${isIncome ? '+ ' : '- '}${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(tx.amount)}", style: TextStyle(fontWeight: FontWeight.bold, color: isTransfer ? Colors.blue : (isIncome ? Colors.green : Colors.red))),
            PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: Icon(Icons.more_vert, size: 18, color: Colors.grey[400]),
              onSelected: (val) {
                if (val == 'delete') _deleteTransaction(tx);
                if (val == 'edit') Navigator.push(context, MaterialPageRoute(builder: (c) => AddTransactionScreen(transactionToEdit: tx)));
              },
              itemBuilder: (context) => [
                if (allowEdit) const PopupMenuItem(value: 'edit', child: Text("Edit")),
                const PopupMenuItem(value: 'delete', child: Text("Hapus")),
              ],
            )
          ])
        ],
      ),
    );
  }

  void _showFilterDialog() {
    showModalBottomSheet(context: context, builder: (context) {
      return StatefulBuilder(
          builder: (context, setStateModal) {
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Filter Transaksi", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 20),

                  // Pilihan Cabang (Hanya Owner)
                  if (_userRole == 'owner') ...[
                    DropdownButtonFormField<String>(
                      value: _selectedBranchFilter,
                      decoration: const InputDecoration(labelText: "Cabang", border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text("Semua Cabang")),
                        DropdownMenuItem(value: 'bst_box', child: Text("Box Factory")),
                        DropdownMenuItem(value: 'm_alfa', child: Text("Maint. Alfa")),
                        DropdownMenuItem(value: 'saufa', child: Text("Saufa Olshop")),
                        DropdownMenuItem(value: 'pusat', child: Text("Kantor Pusat")),
                      ],
                      onChanged: (val) => setStateModal(() => _selectedBranchFilter = val!),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Pilihan Tipe
                  DropdownButtonFormField<String>(
                    value: _selectedType,
                    decoration: const InputDecoration(labelText: "Tipe Transaksi", border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text("Semua")),
                      DropdownMenuItem(value: 'income', child: Text("Pemasukan")),
                      DropdownMenuItem(value: 'expense', child: Text("Pengeluaran")),
                    ],
                    onChanged: (val) => setStateModal(() => _selectedType = val!),
                  ),
                  const SizedBox(height: 12),

                  // Pilihan Tanggal
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                            onPressed: () async {
                              final picked = await showDateRangePicker(context: context, firstDate: DateTime(2023), lastDate: DateTime(2030));
                              if (picked != null) {
                                setStateModal(() { _startDate = picked.start; _endDate = picked.end; });
                              }
                            },
                            child: Text(_startDate == null ? "Pilih Tanggal" : "${DateFormat('dd/MM').format(_startDate!)} - ${DateFormat('dd/MM').format(_endDate!)}")
                        ),
                      ),
                      if (_startDate != null)
                        IconButton(icon: const Icon(Icons.clear), onPressed: () => setStateModal(() { _startDate = null; _endDate = null; }))
                    ],
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
                        onPressed: () {
                          setState(() {}); // Trigger rebuild di screen utama
                          Navigator.pop(context);
                        },
                        child: const Text("Terapkan Filter")
                    ),
                  )
                ],
              ),
            );
          }
      );
    });
  }
}