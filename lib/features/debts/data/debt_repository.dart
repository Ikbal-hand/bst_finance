import 'package:cloud_firestore/cloud_firestore.dart';
// [PENTING] Import ini wajib ada agar DebtModel dikenali
import '../../debts/domain/debt_model.dart';

class DebtRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ===============================================================
  // 1. TAMBAH UTANG (FIX: Menerima Object DebtModel)
  // ===============================================================
  Future<void> addDebt(DebtModel debt) async {
    // Kita simpan data menggunakan fungsi toMap() dari model
    await _firestore.collection('debts').add(debt.toMap());
  }

  // ===============================================================
  // 2. UPDATE UTANG (FIX: Menerima Object DebtModel)
  // ===============================================================
  Future<void> updateDebt(DebtModel debt) async {
    await _firestore.collection('debts').doc(debt.id).update(debt.toMap());
  }

  // ===============================================================
  // 3. HAPUS UTANG (Delete)
  // ===============================================================
  Future<void> deleteDebt(String debtId) async {
    await _firestore.collection('debts').doc(debtId).delete();
  }

  // ===============================================================
  // 4. BAYAR UTANG (Logic Pelunasan)
  // ===============================================================
  Future<void> payDebt({
    required String debtId,
    required String debtName,
    required double payAmount,
    required double currentDebtAmount,
    required String branchId,
    required String walletId,
    required String userId,
  }) async {
    final walletRef = _firestore.collection('wallets').doc(walletId);
    final debtRef = _firestore.collection('debts').doc(debtId);
    final txRef = _firestore.collection('transactions').doc();

    return _firestore.runTransaction((tx) async {
      // A. Baca Saldo
      final walletSnap = await tx.get(walletRef);
      if (!walletSnap.exists) throw Exception("Dompet pembayaran tidak ditemukan: $walletId");

      final currentBalance = (walletSnap.get('balance') ?? 0).toDouble();
      if (currentBalance < payAmount) {
        throw Exception("Saldo tidak cukup untuk membayar utang ini!");
      }

      // B. Potong Saldo
      tx.update(walletRef, {'balance': currentBalance - payAmount});

      // C. Update Sisa Utang
      double sisaUtang = currentDebtAmount - payAmount;
      bool isLunas = sisaUtang <= 100; // Toleransi pembulatan

      if (isLunas) {
        tx.update(debtRef, {
          'amount': 0,
          'status': 'paid',
          'last_payment_at': FieldValue.serverTimestamp()
        });
      } else {
        tx.update(debtRef, {
          'amount': sisaUtang,
          'last_payment_at': FieldValue.serverTimestamp()
        });
      }

      // D. Catat di Riwayat Transaksi
      tx.set(txRef, {
        'amount': payAmount,
        'type': 'expense',
        'category': 'Pelunasan Utang',
        'description': '${isLunas ? "Pelunasan" : "Cicilan"} Utang: $debtName',
        'wallet_id': walletId,
        'related_branch_id': branchId,
        'date': FieldValue.serverTimestamp(),
        'user_id': userId,
        'related_id': debtId, // Link ke ID hutang untuk fitur Smart Delete/Undo
        'deleted_at': null,
      });
    });
  }
}