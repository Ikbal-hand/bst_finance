import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../models/transaction_model.dart';

class TransactionRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ===============================================================
  // 1. TAMBAH TRANSAKSI BARU
  // ===============================================================
  Future<void> addTransaction(TransactionModel transaction) async {
    final walletRef = _firestore.collection('wallets').doc(transaction.walletId);
    final transactionRef = _firestore.collection('transactions').doc();

    return _firestore.runTransaction((tx) async {
      // FASE 1: READ
      final walletSnap = await tx.get(walletRef);
      if (!walletSnap.exists) {
        throw Exception("Dompet tujuan (ID: ${transaction.walletId}) tidak ditemukan!");
      }

      // FASE 2: CALCULATION
      double currentBalance = (walletSnap.get('balance') ?? 0).toDouble();
      double newBalance = 0;

      if (transaction.type == 'expense') {
        if (currentBalance < transaction.amount) {
          final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
          throw Exception("Saldo tidak cukup! Sisa: ${currency.format(currentBalance)}");
        }
        newBalance = currentBalance - transaction.amount;
      } else {
        newBalance = currentBalance + transaction.amount;
      }

      // FASE 3: WRITE
      tx.update(walletRef, {'balance': newBalance});

      final docId = transaction.id.isEmpty ? transactionRef.id : transaction.id;
      final docRef = _firestore.collection('transactions').doc(docId);
      tx.set(docRef, transaction.toMap());
    }).catchError((error) {
      throw error;
    });
  }

  // ===============================================================
  // 2. DELETE TRANSAKSI (FIXED: READ BEFORE WRITE & CASTING)
  // ===============================================================
// ===============================================================
  // 2. DELETE TRANSAKSI (SMART REVERSE APPROVAL)
  // ===============================================================
  Future<void> deleteTransaction(TransactionModel tx) async {
    final walletRef = _firestore.collection('wallets').doc(tx.walletId);
    final txRef = _firestore.collection('transactions').doc(tx.id);

    // Cek apakah ini Transaksi Pelunasan Utang?
    DocumentReference? debtRef;
    if ((tx.category.contains('Utang') || tx.description.contains('Bayar')) && tx.relatedId != null) {
      debtRef = _firestore.collection('debts').doc(tx.relatedId);
    }

    // [BARU] Cek apakah ini Transaksi HASIL APPROVAL?
    // related_type == 'request_approval' dan related_id adalah ID Request
    DocumentReference? originalRequestRef;
    if (tx.relatedType == 'request_approval' && tx.relatedId != null) {
      originalRequestRef = _firestore.collection('requests').doc(tx.relatedId);
    }

    return _firestore.runTransaction((transaction) async {
      // --- FASE 1: READ ---
      final walletSnap = await transaction.get(walletRef);
      if (!walletSnap.exists) throw Exception("Dompet tidak ditemukan!");

      DocumentSnapshot? debtSnap;
      if (debtRef != null) debtSnap = await transaction.get(debtRef);

      DocumentSnapshot? reqSnap;
      if (originalRequestRef != null) reqSnap = await transaction.get(originalRequestRef!);

      // Cari Hutang Sisa (Jika ini adalah Approval Parsial 50%)
      // Kita harus cari hutang yang created_at nya mirip atau source_id nya sama
      // TAPI: Cara paling aman adalah query manual nanti, tapi di runTransaction agak sulit query.
      // Solusi: Kita asumsikan user menghapus transaksi ini, maka status request kembali pending.
      // Hutang sisa akan kita hapus via query terpisah atau biarkan user hapus manual (opsi aman).
      // OPSI TERBAIK: Update status request jadi 'pending'.

      // --- FASE 2: CALCULATION ---
      final walletData = walletSnap.data() as Map<String, dynamic>;
      double currentBalance = (walletData['balance'] ?? 0).toDouble();

      double newBalance = tx.type == 'income'
          ? currentBalance - tx.amount
          : currentBalance + tx.amount;

      // --- FASE 3: WRITE ---

      // A. Update Saldo Wallet
      transaction.update(walletRef, {'balance': newBalance});

      // B. Jika ini Pelunasan Utang -> Kembalikan Utang
      if (debtSnap != null && debtSnap.exists) {
        final debtData = debtSnap.data() as Map<String, dynamic>;
        double currentDebt = (debtData['amount'] ?? 0).toDouble();
        transaction.update(debtRef!, {
          'amount': currentDebt + tx.amount,
          'status': 'unpaid',
        });
      }

      // C. [LOGIC BARU] Jika ini Transaksi Approval -> Reset Request
      if (reqSnap != null && reqSnap.exists) {
        transaction.update(originalRequestRef!, {
          'status': 'pending',          // Kembali Pending (bisa diapprove ulang)
          'approved_amount': 0,         // Reset nominal cair
          'approved_at': null,
          'approver_id': null,
          'note': 'Approval dibatalkan (Transaksi dihapus manual)',
        });

        // CATATAN: Hutang sisa (yang 50% lagi) secara teknis masih ada di database 'debts'.
        // Karena keterbatasan Firestore Transaction (tidak bisa query delete dinamis),
        // Hutang sisa tersebut harus dihapus manual oleh user di menu Hutang,
        // ATAU kita lakukan cleanup terpisah setelah transaksi ini selesai.
      }

      // D. Hapus Transaksi (Soft Delete / Hard Delete sesuai kebutuhan)
      // Disini kita Hard Delete agar bersih
      transaction.delete(txRef);
    });
  }

  // ===============================================================
  // 3. RESTORE (FIXED: CASTING)
  // ===============================================================
  Future<void> restoreTransaction(TransactionModel tx) async {
    final walletRef = _firestore.collection('wallets').doc(tx.walletId);
    final txRef = _firestore.collection('transactions').doc(tx.id);

    DocumentReference? debtRef;
    if (tx.relatedId != null && tx.category.contains('Utang')) {
      debtRef = _firestore.collection('debts').doc(tx.relatedId);
    }

    return _firestore.runTransaction((transaction) async {
      final walletSnap = await transaction.get(walletRef);
      DocumentSnapshot? debtSnap;
      if (debtRef != null) debtSnap = await transaction.get(debtRef);

      if (!walletSnap.exists) throw Exception("Dompet tidak ditemukan");

      // FIX CASTING
      final walletData = walletSnap.data() as Map<String, dynamic>;
      double currentBalance = (walletData['balance'] ?? 0).toDouble();

      double newBalance = tx.type == 'income'
          ? currentBalance + tx.amount
          : currentBalance - tx.amount;

      if (tx.type == 'expense' && newBalance < 0) {
        throw Exception("Gagal Restore! Saldo tidak cukup.");
      }

      transaction.update(walletRef, {'balance': newBalance});

      if (debtSnap != null && debtSnap.exists) {
        final debtData = debtSnap.data() as Map<String, dynamic>;
        double currentDebt = (debtData['amount'] ?? 0).toDouble();
        transaction.update(debtRef!, {
          'amount': currentDebt - tx.amount,
          'status': (currentDebt - tx.amount) <= 100 ? 'paid' : 'unpaid'
        });
      }

      transaction.update(txRef, {
        'deleted_at': null,
        'status': 'active'
      });
    });
  }

  // ===============================================================
  // 4. GET DATA (FIXED: CASTING ERROR DI SINI)
  // ===============================================================
  Stream<List<TransactionModel>> getDeletedTransactions() {
    return _firestore.collection('transactions')
        .where('status', isEqualTo: 'deleted')
        .orderBy('deleted_at', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
      // [FIX UTAMA] Tambahkan 'as Map<String, dynamic>'
      final data = doc.data() as Map<String, dynamic>;
      return TransactionModel.fromMap(data, doc.id);
    }).toList());
  }
  // ===============================================================
  // 5. UPDATE TRANSAKSI (EDIT DENGAN KOREKSI SALDO)
  // ===============================================================
  Future<void> updateTransaction({
    required TransactionModel oldTx,
    required TransactionModel newTx,
  }) async {
    final oldWalletRef = _firestore.collection('wallets').doc(oldTx.walletId);
    final newWalletRef = _firestore.collection('wallets').doc(newTx.walletId);
    final txRef = _firestore.collection('transactions').doc(oldTx.id);

    return _firestore.runTransaction((transaction) async {
      // 1. BACA DATA WALLET
      final oldWalletSnap = await transaction.get(oldWalletRef);
      // Jika dompet berubah, baca dompet baru juga
      DocumentSnapshot? newWalletSnap;
      if (oldTx.walletId != newTx.walletId) {
        newWalletSnap = await transaction.get(newWalletRef);
      } else {
        newWalletSnap = oldWalletSnap; // Referensi sama
      }

      if (!oldWalletSnap.exists) throw Exception("Dompet lama tidak ditemukan");
      if (!newWalletSnap!.exists) throw Exception("Dompet tujuan baru tidak ditemukan");

      // 2. KEMBALIKAN SALDO LAMA (REVERSE OLD)
      // Seolah-olah transaksi lama dihapus dulu
      double oldWalletBal = (oldWalletSnap.data() as Map<String, dynamic>)['balance']?.toDouble() ?? 0;

      // Jika dompet sama, kita pakai variabel temporary agar hitungan berlanjut
      // Jika beda, kita update masing-masing.

      if (oldTx.type == 'income') {
        oldWalletBal -= oldTx.amount; // Tarik kembali uang masuk
      } else {
        oldWalletBal += oldTx.amount; // Refund uang keluar
      }

      // 3. TERAPKAN SALDO BARU (APPLY NEW)
      // Seolah-olah transaksi baru dibuat
      double targetWalletBal;

      // Kasus A: Dompet Sama
      if (oldTx.walletId == newTx.walletId) {
        targetWalletBal = oldWalletBal; // Lanjut dari hasil reverse
      } else {
        // Kasus B: Dompet Beda (Baca saldo dompet baru murni)
        targetWalletBal = (newWalletSnap.data() as Map<String, dynamic>)['balance']?.toDouble() ?? 0;
      }

      if (newTx.type == 'income') {
        targetWalletBal += newTx.amount;
      } else {
        // Cek saldo cukup gak?
        if (targetWalletBal < newTx.amount) {
          throw Exception("Saldo dompet tujuan tidak cukup untuk nominal baru!");
        }
        targetWalletBal -= newTx.amount;
      }

      // 4. WRITE KE DATABASE

      // Update Dompet Lama
      transaction.update(oldWalletRef, {'balance': oldWalletBal});

      // Update Dompet Baru (Jika beda, update doc baru. Jika sama, update doc lama dg nilai baru)
      if (oldTx.walletId != newTx.walletId) {
        transaction.update(newWalletRef, {'balance': targetWalletBal});
      } else {
        // Timpa update sebelumnya agar atomic
        transaction.update(oldWalletRef, {'balance': targetWalletBal});
      }

      // Update Data Transaksi
      transaction.update(txRef, newTx.toMap());
    });
  }

  Future<List<TransactionModel>> getTransactionsByDateRange({
    required DateTime startDate,
    required DateTime endDate,
    String? type,
    String? branchId,
  }) async {
    final start = DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0);
    final end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

    Query query = _firestore.collection('transactions')
        .where('deleted_at', isNull: true)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end));

    if (type != null && type != 'all') {
      query = query.where('type', isEqualTo: type);
    }
    if (branchId != null && branchId != 'all' && branchId != 'pusat') {
      query = query.where('related_branch_id', isEqualTo: branchId);
    }

    final snapshot = await query.orderBy('date', descending: true).get();

    return snapshot.docs.map((doc) {
      // [FIX UTAMA] Tambahkan 'as Map<String, dynamic>'
      final data = doc.data() as Map<String, dynamic>;
      return TransactionModel.fromMap(data, doc.id);
    }).toList();
  }
}