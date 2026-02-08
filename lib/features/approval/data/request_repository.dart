import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

// Pastikan path ini sesuai
import '../../../core/utils/currency_formatter.dart';
import '../../../core/constants/app_colors.dart';

class ApprovalScreen extends StatefulWidget {
  const ApprovalScreen({super.key});

  @override
  State<ApprovalScreen> createState() => _ApprovalScreenState();
}

class _ApprovalScreenState extends State<ApprovalScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- 1. LOGIKA UTAMA: PROSES (ATOMIC TRANSACTION) ---
  Future<void> _processRequest(Map<String, dynamic> req, bool isApproved, {double? approvedAmount}) async {
    // Tampilkan Loading
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => const Center(child: CircularProgressIndicator())
    );

    try {
      final requestRef = _firestore.collection('requests').doc(req['id']);
      // SUMBER DANA: Kas Bendahara Pusat (Level 2)
      final walletRef = _firestore.collection('wallets').doc('treasurer_wallet');

      final user = _auth.currentUser;

      // Hitung Nominal
      double totalRequested = (req['amount'] ?? 0).toDouble();
      double finalAmount = isApproved ? (approvedAmount ?? totalRequested) : 0;
      double sisaUtang = totalRequested - finalAmount;

      await _firestore.runTransaction((tx) async {
        // A. JIKA DISETUJUI -> CEK & POTONG SALDO DULU
        if (isApproved) {
          final walletSnap = await tx.get(walletRef);

          if (!walletSnap.exists) {
            throw Exception("Dompet 'treasurer_wallet' belum dibuat! Hubungi developer.");
          }

          double currentBalance = (walletSnap.data()?['balance'] ?? 0).toDouble();

          if (currentBalance < finalAmount) {
            throw Exception("Saldo Kas Bendahara TIDAK CUKUP untuk menyetujui ini! (Sisa: ${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(currentBalance)})");
          }

          // 1. Potong Saldo
          tx.update(walletRef, {'balance': currentBalance - finalAmount});

          // 2. Catat Transaksi Pengeluaran Pusat
          final newTxRef = _firestore.collection('transactions').doc();
          tx.set(newTxRef, {
            'amount': finalAmount,
            'type': 'expense',
            'category': req['category'] ?? 'Pengeluaran Cabang',
            'description': "Approval: ${req['item_name']} (${req['branch_name']})",
            'wallet_id': 'treasurer_wallet', // Sumber dana yang benar
            'related_branch_id': req['branch_id'],
            'date': FieldValue.serverTimestamp(),
            'user_id': user?.uid ?? 'owner',
            'related_id': req['id'],
            'related_type': 'request_approval',
            'deleted_at': null,
          });

          // 3. Catat Utang (Jika cair sebagian)
          if (sisaUtang > 0) {
            final newDebtRef = _firestore.collection('debts').doc();
            tx.set(newDebtRef, {
              'amount': sisaUtang,
              'branch_id': req['branch_id'],
              'name': "Sisa Approval: ${req['item_name']}",
              'note': "Total Minta: ${NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(totalRequested)}. Cair: ${NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(finalAmount)}",
              'status': 'unpaid',
              'created_at': FieldValue.serverTimestamp(),
              'type': 'payable',
              'source': 'approval',
            });
          }
        }

        // B. UPDATE STATUS REQUEST (Terakhir)
        tx.update(requestRef, {
          'status': isApproved ? 'approved' : 'rejected',
          'approved_at': FieldValue.serverTimestamp(),
          'approver_id': user?.uid ?? 'owner',
          'approved_amount': finalAmount,
          'note': isApproved
              ? (sisaUtang > 0 ? "Cair sebagian. Sisa jadi Utang." : "Disetujui Penuh.")
              : "Permintaan ditolak.",
        });

        // C. KIRIM NOTIFIKASI
        final notifRef = _firestore.collection('notifications').doc();
        tx.set(notifRef, {
          'title': isApproved ? "Permintaan Disetujui" : "Permintaan Ditolak",
          'message': isApproved
              ? "Dana Rp ${NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(finalAmount)} untuk '${req['item_name']}' telah cair."
              : "Maaf, permintaan '${req['item_name']}' ditolak oleh Pusat.",
          'to_branch': req['branch_id'],
          'date': FieldValue.serverTimestamp(),
          'is_read': false,
          'type': 'info',
        });
      });

      if (mounted) {
        Navigator.pop(context); // Tutup Loading
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isApproved ? "Berhasil! Saldo terpotong & Status update." : "Permintaan ditolak."),
              backgroundColor: isApproved ? Colors.green : Colors.red,
            )
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Tutup Loading
        // Bersihkan pesan error agar user friendly
        String errorMsg = e.toString().replaceAll("Exception:", "").trim();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMsg), backgroundColor: Colors.red));
      }
    }
  }

  // --- 2. DIALOG APPROVAL (Tetap Sama) ---
  void _showProcessDialog(BuildContext context, Map<String, dynamic> request) {
    final double totalAmount = (request['amount'] ?? 0).toDouble();
    final nominalCtrl = TextEditingController(
        text: NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(totalAmount).trim()
    );
    final List<int> percentages = [10, 20, 30, 40, 50];

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
                    Text("Total Diminta: Rp ${NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(totalAmount)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),

                    const Text("Pilih Nominal Cepat:", style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: percentages.map((percent) {
                        return ActionChip(
                          label: Text("$percent%"),
                          backgroundColor: Colors.blue.shade50,
                          labelStyle: TextStyle(color: Colors.blue.shade700, fontSize: 12, fontWeight: FontWeight.bold),
                          onPressed: () {
                            double calculated = totalAmount * (percent / 100);
                            final formatted = NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(calculated).trim();
                            setStateDialog(() { nominalCtrl.text = formatted; });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    const Text("Nominal Disetujui (Cair)"),
                    const SizedBox(height: 5),
                    TextFormField(
                      controller: nominalCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [CurrencyInputFormatter()],
                      decoration: const InputDecoration(prefixText: "Rp ", border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                      onChanged: (val) { setStateDialog(() {}); },
                    ),
                    const SizedBox(height: 10),

                    Builder(builder: (c) {
                      String cleanText = nominalCtrl.text.replaceAll('.', '');
                      double inputVal = double.tryParse(cleanText) ?? 0;
                      double sisa = totalAmount - inputVal;
                      if (sisa < 0) sisa = 0;

                      return Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: sisa > 0 ? Colors.orange.shade50 : Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          children: [
                            Icon(sisa > 0 ? Icons.info_outline : Icons.check_circle, size: 16, color: sisa > 0 ? Colors.orange : Colors.green),
                            const SizedBox(width: 8),
                            Expanded(child: Text(sisa > 0 ? "Sisa Rp ${NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(sisa)} jadi UTANG." : "Lunas / Tanpa Utang", style: TextStyle(fontSize: 11, color: sisa > 0 ? Colors.orange.shade900 : Colors.green.shade900))),
                          ],
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
                  onPressed: () {
                    String cleanText = nominalCtrl.text.replaceAll('.', '');
                    double finalAmount = double.parse(cleanText);
                    if (finalAmount > totalAmount) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nominal tidak boleh melebihi permintaan!")));
                      return;
                    }
                    Navigator.pop(ctx);
                    _processRequest(request, true, approvedAmount: finalAmount);
                  },
                  child: const Text("Proses"),
                ),
              ],
            );
          }
      ),
    );
  }

  // --- 3. UI UTAMA (TABS: PENDING & HISTORY) ---
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Persetujuan (Approval)", style: TextStyle(color: Colors.black)),
          backgroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.black),
          elevation: 0,
          bottom: const TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primary,
            tabs: [
              Tab(text: "Perlu Persetujuan"),
              Tab(text: "Riwayat"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildRequestList(isHistory: false), // Tab 1
            _buildRequestList(isHistory: true),  // Tab 2
          ],
        ),
      ),
    );
  }

  Widget _buildRequestList({required bool isHistory}) {
    Query query = _firestore.collection('requests').orderBy('created_at', descending: true);

    if (isHistory) {
      query = query.where('status', whereIn: ['approved', 'rejected']);
    } else {
      query = query.where('status', isEqualTo: 'pending');
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                    isHistory ? Icons.history : Icons.check_circle_outline,
                    size: 80,
                    color: Colors.grey[300]
                ),
                const SizedBox(height: 16),
                Text(
                    isHistory ? "Belum ada riwayat" : "Semua permintaan sudah diproses",
                    style: const TextStyle(color: Colors.grey)
                ),
              ],
            ),
          );
        }

        final requests = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final doc = requests[index];
            final data = doc.data() as Map<String, dynamic>;
            data['id'] = doc.id;

            return _buildRequestCard(data, isHistory);
          },
        );
      },
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> data, bool isHistory) {
    String status = data['status'] ?? 'pending';
    bool isApproved = status == 'approved';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Cabang & Tanggal
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(4)),
                  child: Text(data['branch_name'] ?? 'Cabang', style: TextStyle(fontSize: 10, color: Colors.blue.shade800, fontWeight: FontWeight.bold)),
                ),
                Text(
                  data['created_at'] != null ? DateFormat('dd MMM HH:mm').format((data['created_at'] as Timestamp).toDate()) : '-',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Item & Harga
            Text(data['item_name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text("Kategori: ${data['category'] ?? '-'}", style: const TextStyle(fontSize: 12, color: Colors.grey)),

            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Diminta:", style: TextStyle(fontSize: 10, color: Colors.grey)),
                    Text(
                      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(data['amount'] ?? 0),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                // Jika History, Tampilkan Nominal Cair
                if (isHistory && isApproved)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text("Disetujui (Cair):", style: TextStyle(fontSize: 10, color: Colors.green)),
                      Text(
                        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(data['approved_amount'] ?? 0),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ],
                  ),
              ],
            ),

            if (data['note'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text("Note: ${data['note']}", style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey)),
              ),

            const Divider(height: 24),

            // FOOTER: Tombol (Jika Pending) ATAU Status (Jika History)
            if (!isHistory)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                      onPressed: () => _processRequest(data, false),
                      child: const Text("Tolak"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      onPressed: () => _showProcessDialog(context, data),
                      child: const Text("Setujui"),
                    ),
                  ),
                ],
              )
            else
            // Tampilan Status di Tab History
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isApproved ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isApproved ? Colors.green : Colors.red),
                ),
                child: Center(
                  child: Text(
                    isApproved ? "✅ SUDAH DISETUJUI" : "❌ DITOLAK",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isApproved ? Colors.green.shade700 : Colors.red.shade700
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}