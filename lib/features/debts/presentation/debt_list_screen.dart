import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../debts/domain/debt_model.dart';
import '../data/debt_repository.dart';
import 'add_debt_screen.dart'; // Import screen tambah/edit

class DebtListScreen extends StatefulWidget {
  final String branchId;
  const DebtListScreen({super.key, required this.branchId});

  @override
  State<DebtListScreen> createState() => _DebtListScreenState();
}

class _DebtListScreenState extends State<DebtListScreen> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // LOGIC HAPUS UTANG
  Future<void> _deleteDebt(String debtId) async {
    bool confirm = await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text("Hapus Utang?"),
          content: const Text("Data utang akan dihapus permanen. Pastikan tidak ada transaksi menggantung."),
          actions: [
            TextButton(onPressed: ()=>Navigator.pop(c,false), child: const Text("Batal")),
            TextButton(onPressed: ()=>Navigator.pop(c,true), child: const Text("Hapus", style: TextStyle(color: Colors.red))),
          ],
        )
    ) ?? false;

    if (confirm) {
      await DebtRepository().deleteDebt(debtId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Utang dihapus")));
    }
  }

  // LOGIC BAYAR UTANG (TETAP)
  Future<void> _processPayment(DebtModel debt, double payAmount) async {
    if (payAmount <= 0) return;
    if (payAmount > debt.amount) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pembayaran melebihi sisa utang!"), backgroundColor: Colors.red));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Memproses Pembayaran...")));

    try {
      final user = FirebaseAuth.instance.currentUser;
      const String walletId = 'treasurer_wallet'; // Kas Pusat

      await DebtRepository().payDebt(
        debtId: debt.id,
        debtName: debt.name,
        payAmount: payAmount,
        currentDebtAmount: debt.amount,
        branchId: widget.branchId,
        walletId: walletId,
        userId: user?.uid ?? 'unknown',
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Berhasil dibayar: ${_formatRupiah(payAmount)}"),
            backgroundColor: Colors.green
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    }
  }

  // DIALOG BAYAR (SAMA SEPERTI SEBELUMNYA, DISINGKAT)
  void _showPaymentDialog(BuildContext context, DebtModel debt) {
    final nominalCtrl = TextEditingController();
    final List<int> percentages = [25, 50, 75, 100];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (context, setStateDialog) {
            double inputVal = double.tryParse(nominalCtrl.text.replaceAll('.', '')) ?? 0;
            double sisaNanti = debt.amount - inputVal;
            if (sisaNanti < 0) sisaNanti = 0;

            return AlertDialog(
              title: const Text("Bayar Utang", style: TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                      child: const Text("Sumber Dana: KAS BENDAHARA PUSAT", style: TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 16),
                    Text("Sisa: ${_formatRupiah(debt.amount)}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: percentages.map((percent) {
                        return ActionChip(
                          label: Text(percent == 100 ? "Lunas" : "$percent%"),
                          onPressed: () {
                            double calc = debt.amount * (percent / 100);
                            setStateDialog(() {
                              nominalCtrl.text = NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(calc).trim();
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nominalCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [CurrencyInputFormatter()],
                      decoration: const InputDecoration(labelText: "Nominal Bayar", prefixText: "Rp ", border: OutlineInputBorder()),
                      onChanged: (val) => setStateDialog((){}),
                    ),
                    if (inputVal > 0)
                      Text("Sisa nanti: ${_formatRupiah(sisaNanti)}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange))
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: () {
                    double amount = double.tryParse(nominalCtrl.text.replaceAll('.', '')) ?? 0;
                    _processPayment(debt, amount);
                  },
                  child: const Text("Bayar"),
                )
              ],
            );
          }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("Daftar Utang", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppColors.primary,
          tabs: const [Tab(text: "Vendor / Manual"), Tab(text: "Sisa Approval")],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDebtList(isApprovalDebt: false),
          _buildDebtList(isApprovalDebt: true),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.black,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () {
          // Navigasi ke Halaman AddDebtScreen
          Navigator.push(context, MaterialPageRoute(builder: (c) => const AddDebtScreen()));
        },
      ),
    );
  }

  Widget _buildDebtList({required bool isApprovalDebt}) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('debts')
          .where('branch_id', isEqualTo: widget.branchId)
          .orderBy('created_at', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return _emptyState();

        final docs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          String source = (data['source'] ?? 'manual').toString();
          if (isApprovalDebt) return source.contains('approval');
          return !source.contains('approval');
        }).toList();

        if (docs.isEmpty) return _emptyState();

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final debt = DebtModel.fromMap(data, docs[index].id);
            return _buildDebtCard(debt, isApprovalDebt);
          },
        );
      },
    );
  }

  Widget _emptyState() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.check_circle_outline, size: 60, color: Colors.grey[300]), const SizedBox(height: 10), Text("Tidak ada tagihan", style: TextStyle(color: Colors.grey[400]))]));
  }

  Widget _buildDebtCard(DebtModel debt, bool isApprovalDebt) {
    bool isPaid = debt.status == 'paid';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(debt.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      if (isApprovalDebt)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(4)),
                          child: const Text("Sisa Approval", style: TextStyle(fontSize: 10, color: Colors.blue)),
                        ),
                    ],
                  ),
                ),

                // [PERBAIKAN] Menu Edit & Hapus sekarang muncul untuk SEMUA jenis hutang (selama belum lunas)
                if (!isPaid)
                  PopupMenuButton<String>(
                    onSelected: (val) {
                      if (val == 'edit') {
                        // Navigasi ke Edit Screen
                        Navigator.push(context, MaterialPageRoute(builder: (c) => AddDebtScreen(debtToEdit: debt)));
                      } else if (val == 'delete') {
                        _deleteDebt(debt.id);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 16, color: Colors.blue), SizedBox(width: 8), Text("Edit")])),
                      const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 16, color: Colors.red), SizedBox(width: 8), Text("Hapus")])),
                    ],
                    child: const Icon(Icons.more_vert, color: Colors.grey),
                  ),
              ],
            ),

            // INFO TAMBAHAN: TANGGAL & BANK
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 12, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text("Tempo: ", style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                Text(DateFormat('dd MMM yy').format(debt.dueDate), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red)),
              ],
            ),

            if (debt.bankName != null && debt.bankName!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(Icons.account_balance, size: 12, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text("${debt.bankName} - ${debt.accountNumber}", style: TextStyle(fontSize: 11, color: Colors.grey[800], fontWeight: FontWeight.w500)),
                  ],
                ),
              ),

            const Divider(height: 20),

            // TOMBOL BAYAR / STATUS LUNAS
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text("Sisa Tagihan", style: TextStyle(fontSize: 10, color: Colors.grey)),
                  Text(_formatRupiah(debt.amount), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isPaid ? Colors.green : Colors.red)),
                ]),

                if (!isPaid)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                    onPressed: () => _showPaymentDialog(context, debt),
                    child: const Text("Bayar", style: TextStyle(fontSize: 12)),
                  )
                else
                  const Chip(label: Text("LUNAS", style: TextStyle(fontSize: 10, color: Colors.white)), backgroundColor: Colors.green)
              ],
            )
          ],
        ),
      ),
    );
  }

  String _formatRupiah(double amount) => NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(amount);
}