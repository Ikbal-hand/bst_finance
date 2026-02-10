import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../data/request_repository.dart';
import '../domain/request_model.dart';

class ApprovalScreen extends StatefulWidget {
  const ApprovalScreen({super.key});

  @override
  State<ApprovalScreen> createState() => _ApprovalScreenState();
}

class _ApprovalScreenState extends State<ApprovalScreen> {
  final RequestRepository _repo = RequestRepository();
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? 'owner';

  // --- LOGIC DIALOG ---
  void _showProcessDialog(BuildContext context, RequestModel request) {
    final double totalAmount = request.amount;
    final nominalCtrl = TextEditingController(
        text: NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(totalAmount).trim()
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("Proses Approval"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(request.description, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text("Total Diminta: Rp ${NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(totalAmount)}"),

                    const SizedBox(height: 16),
                    const Text("Nominal Disetujui (Cair)"),
                    TextFormField(
                      controller: nominalCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [CurrencyInputFormatter()],
                      decoration: const InputDecoration(prefixText: "Rp ", border: OutlineInputBorder()),
                      onChanged: (val) => setStateDialog(() {}),
                    ),

                    // Info Sisa Hutang
                    Builder(builder: (c) {
                      double inputVal = double.tryParse(nominalCtrl.text.replaceAll('.', '')) ?? 0;
                      double sisa = totalAmount - inputVal;

                      // [FIX] Menggunakan NumberFormat.currency biasa
                      final currencyFmt = NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0);

                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          sisa > 0 ? "Sisa Rp ${currencyFmt.format(sisa)} akan jadi UTANG." : "Lunas / Penuh",
                          style: TextStyle(color: sisa > 0 ? Colors.orange : Colors.green, fontSize: 12),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: () async {
                    double finalAmount = double.tryParse(nominalCtrl.text.replaceAll('.', '')) ?? 0;
                    if (finalAmount > totalAmount) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nominal tidak boleh melebihi permintaan!")));
                      return;
                    }

                    Navigator.pop(ctx);
                    _executeProcess(request, true, approvedAmount: finalAmount);
                  },
                  child: const Text("Proses"),
                ),
              ],
            );
          }
      ),
    );
  }

  Future<void> _executeProcess(RequestModel req, bool isApproved, {double? approvedAmount}) async {
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));

    try {
      await _repo.processRequest(
        requestId: req.id,
        isApproved: isApproved,
        approverId: _currentUserId,
        approvedAmount: approvedAmount,
        branchId: req.branchId,
        category: req.category,
        description: req.description,
        totalRequested: req.amount,
        note: isApproved ? null : "Ditolak via Aplikasi",
      );

      if (mounted) {
        Navigator.pop(context); // Tutup Loading
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isApproved ? "Berhasil Disetujui" : "Permintaan Ditolak"),
          backgroundColor: isApproved ? Colors.green : Colors.red,
        ));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    }
  }

  // --- UI LIST ---
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Persetujuan", style: TextStyle(color: Colors.black)),
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black),
          bottom: const TabBar(
            labelColor: AppColors.primary,
            tabs: [Tab(text: "Menunggu"), Tab(text: "Riwayat")],
          ),
        ),
        body: TabBarView(
          children: [
            _buildList(isHistory: false),
            _buildList(isHistory: true),
          ],
        ),
      ),
    );
  }

  Widget _buildList({required bool isHistory}) {
    Query query = FirebaseFirestore.instance.collection('requests').orderBy('created_at', descending: true);
    if (isHistory) {
      query = query.where('status', whereIn: ['approved', 'rejected']);
    } else {
      query = query.where('status', isEqualTo: 'pending');
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return Center(child: Text(isHistory ? "Belum ada riwayat" : "Tidak ada permintaan baru"));

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final req = RequestModel.fromMap(docs[index].data() as Map<String, dynamic>, docs[index].id);
            return _buildCard(req, isHistory);
          },
        );
      },
    );
  }

  Widget _buildCard(RequestModel req, bool isHistory) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  color: Colors.blue[50],
                  child: Text(req.branchName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.blue)),
                ),
                Text(DateFormat('dd MMM HH:mm').format(req.createdAt), style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            Text(req.description, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(req.category, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            Text("Rp ${NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(req.amount)}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),

            if (!isHistory) ...[
              const Divider(),
              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: () => _executeProcess(req, false), child: const Text("Tolak", style: TextStyle(color: Colors.red)))),
                  const SizedBox(width: 10),
                  Expanded(child: ElevatedButton(onPressed: () => _showProcessDialog(context, req), style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text("Proses"))),
                ],
              )
            ] else ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: req.status == 'approved' ? Colors.green[50] : Colors.red[50],
                child: Text(req.status.toUpperCase(), textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: req.status == 'approved' ? Colors.green : Colors.red)),
              )
            ]
          ],
        ),
      ),
    );
  }
}