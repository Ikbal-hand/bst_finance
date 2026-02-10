import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/transaction_model.dart';
import '../../transactions/data/transaction_repository.dart';

class TrashbinScreen extends StatelessWidget {
  const TrashbinScreen({super.key});

  // [FIX] Terima Model, bukan String ID
  Future<void> _restore(BuildContext context, TransactionModel tx) async {
    try {
      await TransactionRepository().restoreTransaction(tx);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Transaksi dipulihkan.")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sampah (Trash)"), backgroundColor: Colors.white, foregroundColor: Colors.black),
      // [FIX] Ubah generic type StreamBuilder jadi List<TransactionModel>
      body: StreamBuilder<List<TransactionModel>>(
        stream: TransactionRepository().getDeletedTransactions(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));

          final transactions = snapshot.data ?? [];
          if (transactions.isEmpty) return const Center(child: Text("Sampah kosong"));

          return ListView.builder(
            itemCount: transactions.length,
            itemBuilder: (context, index) {
              final tx = transactions[index];
              return ListTile(
                title: Text(tx.category),
                subtitle: Text("${DateFormat('dd/MM/yy').format(tx.date)} • ${tx.description}"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Rp ${NumberFormat.compact().format(tx.amount)}", style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey)),
                    IconButton(
                      icon: const Icon(Icons.restore, color: Colors.green),
                      // [FIX] Kirim tx (Model)
                      onPressed: () => _restore(context, tx),
                    )
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}