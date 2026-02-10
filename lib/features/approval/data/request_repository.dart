import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../domain/request_model.dart';

class RequestRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 1. BUAT REQUEST BARU + NOTIFIKASI KE PUSAT
  Future<void> createRequest(RequestModel request) async {
    WriteBatch batch = _firestore.batch();

    // A. Simpan Dokumen Request
    DocumentReference reqRef = _firestore.collection('requests').doc();
    Map<String, dynamic> reqData = request.toMap();
    batch.set(reqRef, reqData);

    // B. Simpan Dokumen Notifikasi (Untuk Bendahara Pusat)
    DocumentReference notifRef = _firestore.collection('notifications').doc();

    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    String formattedAmount = currency.format(request.amount);

    batch.set(notifRef, {
      'title': 'Permintaan Dana Baru',
      'message': '${request.branchName} meminta $formattedAmount untuk ${request.category}',
      'type': 'approval_request',

      // [PENTING] Kirim ke 'pusat' agar terbaca oleh Owner/Bendahara
      'to_branch': 'pusat',
      'is_read': false,
      'related_id': reqRef.id,

      // [PENTING] Pakai 'date' bukan 'created_at', sesuai NotificationScreen Anda
      'date': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  // 2. GET PENDING REQUESTS
  Stream<List<RequestModel>> getPendingRequests() {
    return _firestore.collection('requests')
        .where('status', isEqualTo: 'pending')
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return RequestModel.fromMap(doc.data(), doc.id);
      }).toList();
    });
  }

  // 3. APPROVE / REJECT REQUEST + NOTIF BALIK
  Future<void> processRequest({
    required String requestId,
    required bool isApproved,
    double? approvedAmount,
    required String approverId,
    String? note,
    required String branchId,
    required String category,
    required String description,
    required double totalRequested,
  }) async {
    final requestRef = _firestore.collection('requests').doc(requestId);
    final walletRef = _firestore.collection('wallets').doc('treasurer_wallet');

    return _firestore.runTransaction((tx) async {
      // --- LOGIC APPROVAL ---
      if (isApproved) {
        final walletSnap = await tx.get(walletRef);
        if (!walletSnap.exists) throw Exception("Dompet Pusat tidak ditemukan!");

        double currentBalance = (walletSnap.data()?['balance'] ?? 0).toDouble();
        double finalAmount = approvedAmount ?? totalRequested;

        if (currentBalance < finalAmount) {
          throw Exception("Saldo Kas Pusat Tidak Cukup!");
        }

        // Potong Saldo
        tx.update(walletRef, {'balance': currentBalance - finalAmount});

        // Catat Pengeluaran
        final newTxRef = _firestore.collection('transactions').doc();
        tx.set(newTxRef, {
          'amount': finalAmount,
          'type': 'expense',
          'category': category,
          'description': "Approval: $description",
          'wallet_id': 'treasurer_wallet',
          'related_branch_id': branchId,
          'date': FieldValue.serverTimestamp(),
          'user_id': approverId,
          'related_id': requestId,
          'related_type': 'request_approval',
          'status': 'success',
          'created_at': FieldValue.serverTimestamp(),
          'deleted_at': null,
        });

        // Catat Hutang Sisa (Jika Parsial)
        double sisa = totalRequested - finalAmount;
        if (sisa > 0) {
          final debtRef = _firestore.collection('debts').doc();
          tx.set(debtRef, {
            'amount': sisa,
            'branch_id': branchId,
            'name': "Sisa Approval: $description",
            'note': "Total: $totalRequested. Cair: $finalAmount",
            'status': 'unpaid',
            'created_at': FieldValue.serverTimestamp(),
            'type': 'payable', // Hutang dagang/payable
            'source': 'approval',
            'related_request_id': requestId,
            'loan_date': FieldValue.serverTimestamp(),
            'due_date': FieldValue.serverTimestamp(),
          });
        }
      }

      // Update Status Request
      tx.update(requestRef, {
        'status': isApproved ? 'approved' : 'rejected',
        'approved_at': FieldValue.serverTimestamp(),
        'approver_id': approverId,
        'approved_amount': isApproved ? (approvedAmount ?? totalRequested) : 0,
        'note': note ?? (isApproved ? "Disetujui" : "Ditolak"),
      });

      // [TAMBAHAN] Kirim Notifikasi Balik ke Cabang Peminta
      final notifBackRef = _firestore.collection('notifications').doc();
      tx.set(notifBackRef, {
        'title': isApproved ? 'Permintaan Disetujui' : 'Permintaan Ditolak',
        'message': isApproved
            ? 'Dana untuk $description telah cair.'
            : 'Permintaan $description ditolak oleh Pusat.',
        'type': 'approval_result',

        // Kirim balik ke ID Cabang yang meminta
        'to_branch': branchId,
        'is_read': false,
        'date': FieldValue.serverTimestamp(), // Pakai 'date' sesuai UI
      });
    });
  }
}