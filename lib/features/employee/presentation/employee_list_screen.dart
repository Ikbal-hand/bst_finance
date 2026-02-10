import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/employee_repository.dart';
import '../domain/employee_model.dart';
import 'add_employee_screen.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../../models/transaction_model.dart';
import '../../../core/constants/app_colors.dart'; // Pastikan import warna

class EmployeeListScreen extends StatelessWidget {
  final String branchId;
  const EmployeeListScreen({super.key, required this.branchId});

  // --- 1. FITUR KIRIM SLIP GAJI VIA WA (DIPERBAIKI) ---
  Future<void> _sendWhatsAppSlip(BuildContext context, EmployeeModel employee) async {
    // Format Nomor HP (62xxx)
    String phone = employee.phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (phone.startsWith('0')) {
      phone = "62${phone.substring(1)}";
    }

    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final salaryStr = currency.format(employee.baseSalary);
    final dateStr = DateFormat('dd MMMM yyyy', 'id_ID').format(DateTime.now());

    String message =
        "*SLIP GAJI - BST FINANCE*\n"
        "----------------------------------\n"
        "Nama   : ${employee.name}\n"
        "Jabatan: ${employee.position}\n"
        "Tanggal: $dateStr\n"
        "----------------------------------\n"
        "*TOTAL DITERIMA: $salaryStr*\n"
        "----------------------------------\n"
        "Terima kasih atas kerja keras Anda!\n"
        "Simpan pesan ini sebagai bukti sah.";

    // Gunakan URL scheme standar yang lebih aman
    final Uri url = Uri.parse("https://wa.me/$phone?text=${Uri.encodeComponent(message)}");

    try {
      // mode: LaunchMode.externalApplication memaksa membuka aplikasi lain (Browser/WA)
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw 'Could not launch WhatsApp';
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Gagal membuka WhatsApp. Pastikan terinstall.")),
        );
      }
    }
  }

  // Helper: Cek apakah bulan ini sudah gajian?
  bool _isPaidThisMonth(DateTime? lastPaid) {
    if (lastPaid == null) return false;
    final now = DateTime.now();
    return lastPaid.month == now.month && lastPaid.year == now.year;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("Manajemen Pegawai"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blue,
        child: const Icon(Icons.person_add, color: Colors.white),
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(
            builder: (c) => AddEmployeeScreen(branchId: branchId),
          ));
        },
      ),
      body: StreamBuilder<List<EmployeeModel>>(
        stream: EmployeeRepository().getEmployees(branchId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("Belum ada pegawai."));
          }

          final employees = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: employees.length,
            itemBuilder: (context, index) {
              final employee = employees[index];
              return _buildEmployeeCard(context, employee);
            },
          );
        },
      ),
    );
  }

  Widget _buildEmployeeCard(BuildContext context, EmployeeModel employee) {
    // Cek Status Gaji
    bool isPaid = _isPaidThisMonth(employee.lastPaidAt);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            Row(
              children: [
                // FOTO PROFIL
                CircleAvatar(
                  backgroundColor: Colors.blue.shade100,
                  child: Text(
                    employee.name.isNotEmpty ? employee.name[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),

                // NAMA & JABATAN
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(employee.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(employee.position, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),

                // TOMBOL WA
                IconButton(
                  icon: const Icon(Icons.perm_phone_msg, color: Colors.green),
                  tooltip: "Kirim Slip WA",
                  onPressed: () => _sendWhatsAppSlip(context, employee),
                ),

                // TOMBOL OPSI
                IconButton(
                  icon: const Icon(Icons.more_vert, color: Colors.grey),
                  onPressed: () => _showOptions(context, employee, isPaid),
                ),
              ],
            ),

            const Divider(),

            // INFO BAWAH: GAJI & STATUS
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Nominal Gaji
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Gaji Pokok", style: TextStyle(fontSize: 10, color: Colors.grey)),
                    Text(
                      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(employee.baseSalary),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),

                // STATUS PEMBAYARAN (BADGE)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isPaid ? Colors.green.shade100 : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isPaid ? Colors.green : Colors.orange),
                  ),
                  child: Row(
                    children: [
                      Icon(
                          isPaid ? Icons.check_circle : Icons.history_toggle_off,
                          size: 14,
                          color: isPaid ? Colors.green.shade700 : Colors.orange.shade800
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isPaid ? "LUNAS (Bln Ini)" : "BELUM GAJIAN",
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isPaid ? Colors.green.shade700 : Colors.orange.shade800
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  void _showOptions(BuildContext context, EmployeeModel employee, bool isPaid) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // JUDUL SHEET
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text("Atur Pegawai: ${employee.name}", style: const TextStyle(fontWeight: FontWeight.bold)),
          ),

          // OPSI 1: BAYAR GAJI
          ListTile(
            leading: Icon(Icons.monetization_on, color: isPaid ? Colors.grey : Colors.green),
            title: Text(isPaid ? "Sudah Dibayar Bulan Ini" : "Bayar Gaji Sekarang"),
            subtitle: isPaid
                ? const Text("Klik untuk bayar ulang (Bonus/THR)")
                : const Text("Potong dari KAS PUSAT"),
            enabled: true, // Tetap bisa diklik walau sudah lunas (untuk koreksi/bonus)
            onTap: () {
              Navigator.pop(ctx);
              _confirmPaySalary(context, employee, isPaid);
            },
          ),
          const Divider(),

          // OPSI 2: EDIT
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.blue),
            title: const Text("Edit Pegawai"),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(
                builder: (c) => AddEmployeeScreen(
                  branchId: employee.branchId,
                  branchName: employee.branchName,
                  employeeToEdit: employee,
                ),
              ));
            },
          ),

          // OPSI 3: HAPUS
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text("Hapus Pegawai"),
            onTap: () {
              Navigator.pop(ctx);
              _confirmDelete(context, employee);
            },
          ),
        ],
      ),
    );
  }

  void _confirmPaySalary(BuildContext context, EmployeeModel employee, bool isAlreadyPaid) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Konfirmasi Penggajian"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Bayar gaji untuk ${employee.name}?"),
            const SizedBox(height: 10),
            Text(
              "Nominal: Rp ${NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(employee.baseSalary)}",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),
            if (isAlreadyPaid)
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.orange.shade50,
                child: const Text(
                  "PERINGATAN: Pegawai ini tercatat SUDAH dibayar bulan ini. Lanjutkan pembayaran double?",
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
            const SizedBox(height: 5),
            const Text("Dana akan dipotong dari: KAS PUSAT", style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              Navigator.pop(ctx);

              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Memproses Pembayaran...")));

              try {
                final user = FirebaseAuth.instance.currentUser;
                if (user == null) throw Exception("User tidak terdeteksi");

                final newTx = TransactionModel(
                  id: '',
                  amount: employee.baseSalary,
                  type: 'expense',
                  category: 'Gaji Karyawan',
                  description: 'Gaji ${employee.name} (${DateFormat('MMMM yyyy', 'id_ID').format(DateTime.now())})',
                  walletId: 'main_cash',
                  date: DateTime.now(),
                  userId: user.uid,
                  relatedBranchId: employee.branchId, createdAt: DateTime.now(),
                );

                await TransactionRepository().addTransaction(newTx);

                // UPDATE FIELD 'last_paid_at'
                await EmployeeRepository().updateEmployee(employee.id, {
                  'last_paid_at': Timestamp.now()
                });

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gaji Berhasil Dibayarkan!")));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e")));
                }
              }
            },
            child: const Text("Bayar Sekarang"),
          )
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, EmployeeModel employee) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Hapus Pegawai?"),
        content: Text("Yakin ingin menghapus ${employee.name}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await EmployeeRepository().deleteEmployee(employee.id);
            },
            child: const Text("Hapus", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}