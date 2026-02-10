import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/database_seeder.dart'; // [IMPORT SEEDER]
import '../../../dummy_data_generator.dart';
import '../../auth/login_screen.dart';
import 'trashbin_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  User? _user;
  Map<String, dynamic>? _userData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    _user = FirebaseAuth.instance.currentUser;
    if (_user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(_user!.uid).get();
      if (doc.exists) {
        setState(() {
          _userData = doc.data();
          _isLoading = false;
        });
      }
    }
  }

  // --- LOGIKA DEVELOPER ---
  void _handleResetData() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("⚠️ BAHAYA: Reset Data"),
        content: const Text("Semua transaksi, utang, pegawai, dan notifikasi akan DIHAPUS PERMANEN. Saldo dompet akan jadi 0.\n\nApakah Anda yakin?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              _performAction(() => DatabaseSeeder().clearAllData(), "Database Berhasil Dikosongkan!");
            },
            child: const Text("YA, HAPUS SEMUA"),
          )
        ],
      ),
    );
  }
  Future<void> _handleGenerateDummy() async {
    // 1. Tampilkan Dialog Konfirmasi (Agar tidak terpencet tidak sengaja)
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Generate Data Dummy?"),
        content: const Text(
            "Sistem akan membuat puluhan transaksi simulasi (Rasional) dari tanggal 1-30 bulan ini.\n\n"
                "Data mencakup:\n"
                "• Penjualan Harian (Box, Alfa, Saufa)\n"
                "• Pengeluaran Operasional (Makan, Bensin)\n"
                "• Project Besar & Belanja Stok\n"
                "• Gaji Karyawan"
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Batal", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text("Ya, Gas Pol!"),
          ),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    // 2. Tampilkan Loading (Block UI)
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text("Sedang meracik data..."),
                ],
              ),
            ),
          ),
        ),
      );
    }

    try {
      // 3. PANGGIL GENERATOR
      await DummyDataGenerator().generateRationalData();

      // 4. Sukses
      if (mounted) {
        Navigator.pop(context); // Tutup Loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Data Dummy Berhasil Dibuat! Silakan cek Laporan."),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // 5. Gagal
      if (mounted) {
        Navigator.pop(context); // Tutup Loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Gagal generate data: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  Future<void> _performAction(Future<void> Function() action, String successMsg) async {
    setState(() => _isLoading = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sedang memproses...")));
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMsg), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  // ------------------------

  void _handleLogout() async {
    // ... (Kode Logout Anda tetap sama) ...
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
            (Route<dynamic> route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    bool isOwner = _userData?['role'] == 'owner';

    return Scaffold(
      backgroundColor: AppColors.bgScaffold,
      appBar: AppBar(
        title: const Text("Pengaturan", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // PROFIL HEADER
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                const CircleAvatar(radius: 30, backgroundColor: Colors.white, child: Icon(Icons.person, size: 30, color: AppColors.primary)),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_userData?['name'] ?? 'User', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                    Text(_userData?['email'] ?? '-', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
                      child: Text(isOwner ? "OWNER / PUSAT" : "ADMIN CABANG", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    )
                  ],
                )
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Text("Akun & Keamanan", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 12),

          _buildSettingsItem(Icons.lock_outline, "Ganti Password", "Ubah kata sandi akun anda", () {}),

          if (isOwner)
            _buildSettingsItem(
                Icons.delete_sweep_outlined,
                "Trashbin (Sampah)",
                "Lihat & pulihkan transaksi",
                    () => Navigator.push(context, MaterialPageRoute(builder: (c) => const TrashbinScreen()))
            ),

          // --- MENU DEVELOPER (KHUSUS OWNER) ---
          if (isOwner) ...[
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  border: Border.all(color: Colors.orange),
                  borderRadius: BorderRadius.circular(12)
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange),
                      SizedBox(width: 8),
                      Text("DEVELOPER ZONE", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                    ],
                  ),
                  const Divider(),

                  // TOMBOL 1: GENERATE DUMMY
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.playlist_add_check_circle, color: Colors.green),
                    title: const Text("Isi Data Dummy"),
                    subtitle: const Text("Buat data palsu untuk demo"),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _handleGenerateDummy,
                  ),

                  // TOMBOL 2: HAPUS DATA
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.delete_forever, color: Colors.red),
                    title: const Text("Kosongkan Database"),
                    subtitle: const Text("Reset aplikasi ke 0 (Hati-hati!)"),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _handleResetData,
                  ),
                ],
              ),
            ),
          ],
          // // -------------------------------------

          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _handleLogout,
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[50],
                  foregroundColor: Colors.red,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
              ),
              icon: const Icon(Icons.logout),
              label: const Text("Keluar Aplikasi"),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildSettingsItem(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: Colors.black87, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}