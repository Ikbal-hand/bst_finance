import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'models/transaction_model.dart'; // Sesuaikan import model Anda

class DummyDataGenerator {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Random _rnd = Random();

  Future<void> generateRationalData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print("User belum login!");
      return;
    }

    print("🚀 MULAI GENERATE DUMMY DATA...");

    // Tentukan Periode (Bulan Ini)
    DateTime now = DateTime.now();
    int year = now.year;
    int month = now.month;
    int lastDay = 30; // Simulasi sampai tanggal 30

    // List Cabang
    List<String> branches = ['bst_box', 'm_alfa', 'saufa'];

    // Batch Write agar cepat & atomic
    WriteBatch batch = _firestore.batch();
    int batchCount = 0;

    for (int day = 1; day <= lastDay; day++) {
      DateTime currentDate = DateTime(year, month, day, 8 + _rnd.nextInt(10), _rnd.nextInt(59));

      // --- 1. PEMASUKAN HARIAN (SALES) ---
      // Setiap cabang pasti ada penjualan harian kecil-kecil
      for (var branch in branches) {
        // Random Sales: Rp 100.000 - Rp 1.500.000
        double sales = (100000 + _rnd.nextInt(1400000)).toDouble();
        _addToBatch(batch, _createTx(
          amount: sales,
          type: 'income',
          category: 'Penjualan',
          desc: 'Penjualan Harian ($branch)',
          branch: branch,
          date: currentDate,
          user: user.uid,
          wallet: 'petty_${branch.split('_').last}', // petty_box, petty_alfa, etc
        ));
      }

      // --- 2. PENGELUARAN HARIAN (OPERASIONAL) ---
      // Uang Makan & Bensin (Pasti ada tiap hari)
      for (var branch in branches) {
        double makan = 50000 + _rnd.nextInt(50000).toDouble(); // 50rb - 100rb
        _addToBatch(batch, _createTx(
          amount: makan,
          type: 'expense',
          category: 'Harian',
          desc: 'Uang Makan & Bensin Tim',
          branch: branch,
          date: currentDate,
          user: user.uid,
          wallet: 'petty_${branch.split('_').last}',
        ));
      }

      // --- 3. PROJECT BESAR (MINGGUAN / RANDOM) ---
      // Terjadi setiap ~5 hari sekali di cabang Box Factory
      if (day % 5 == 0 || _rnd.nextInt(10) > 8) {
        double projectValue = (5000000 + _rnd.nextInt(20000000)).toDouble(); // 5jt - 25jt
        _addToBatch(batch, _createTx(
          amount: projectValue,
          type: 'income',
          category: 'Proyek',
          desc: 'Pelunasan Project Batch #${_rnd.nextInt(100)}',
          branch: 'bst_box', // Biasanya box factory yg project gede
          date: currentDate,
          user: user.uid,
          wallet: 'company_wallet', // Masuk ke Pusat
        ));
      }

      // --- 4. BELANJA BAHAN BAKU (MINGGUAN) ---
      // Setiap hari Senin (anggap tgl 7, 14, 21, 28)
      if (day % 7 == 0) {
        double belanja = (2000000 + _rnd.nextInt(3000000)).toDouble();
        _addToBatch(batch, _createTx(
          amount: belanja,
          type: 'expense',
          category: 'Belanja Perusahaan',
          desc: 'Restock Material Mingguan',
          branch: 'bst_box',
          date: currentDate,
          user: user.uid,
          wallet: 'treasurer_wallet', // Bayar pakai kas pusat
        ));
      }

      // --- 5. GAJI KARYAWAN (TANGGAL 25/28) ---
      if (day == 25) {
        _addToBatch(batch, _createTx(
          amount: 15000000,
          type: 'expense',
          category: 'Gaji',
          desc: 'Payroll Karyawan Bulan Ini',
          branch: 'pusat',
          date: currentDate,
          user: user.uid,
          wallet: 'treasurer_wallet',
        ));
      }
    }

    // Commit sisa batch
    await batch.commit();
    print("✅ SELESAI! Data Dummy Berhasil Dibuat.");
  }

  // Helper untuk membuat Object TransactionModel -> Map
  TransactionModel _createTx({
    required double amount,
    required String type,
    required String category,
    required String desc,
    required String branch,
    required DateTime date,
    required String user,
    required String wallet,
  }) {
    // Generate ID unik
    String id = _firestore.collection('transactions').doc().id;

    return TransactionModel(
      id: id,
      amount: amount,
      type: type,
      category: category,
      description: desc,
      walletId: wallet,
      date: date,
      userId: user,
      relatedBranchId: branch,
      status: 'success',
      createdAt: DateTime.now(),
      // Field lain null/default
    );
  }

  void _addToBatch(WriteBatch batch, TransactionModel tx) {
    DocumentReference ref = _firestore.collection('transactions').doc(tx.id);
    batch.set(ref, tx.toMap());
  }
}