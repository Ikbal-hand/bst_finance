import 'package:cloud_firestore/cloud_firestore.dart';

class DebtModel {
  final String id;
  final String name;
  final double amount;
  final String branchId;
  final String note;
  final String status; // 'paid' or 'unpaid'
  final String type; // 'payable' (Utang kita) or 'receivable' (Piutang)
  final String source; // 'manual' or 'approval'
  final DateTime createdAt;

  // Field Baru
  final DateTime loanDate; // Tanggal Pinjam
  final DateTime dueDate;  // Jatuh Tempo
  final String? bankName;
  final String? accountNumber;

  DebtModel({
    required this.id,
    required this.name,
    required this.amount,
    required this.branchId,
    required this.note,
    required this.status,
    required this.type,
    required this.source,
    required this.createdAt,
    required this.loanDate,
    required this.dueDate,
    this.bankName,
    this.accountNumber,
  });

  factory DebtModel.fromMap(Map<String, dynamic> map, String id) {
    return DebtModel(
      id: id,
      name: map['name'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      branchId: map['branch_id'] ?? '',
      note: map['note'] ?? '',
      status: map['status'] ?? 'unpaid',
      type: map['type'] ?? 'payable',
      source: map['source'] ?? 'manual',
      createdAt: (map['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),

      // Mapping Field Baru (dengan fallback agar tidak error data lama)
      loanDate: (map['loan_date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      dueDate: (map['due_date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      bankName: map['bank_name'],
      accountNumber: map['account_number'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'amount': amount,
      'branch_id': branchId,
      'note': note,
      'status': status,
      'type': type,
      'source': source,
      'created_at': Timestamp.fromDate(createdAt),
      'loan_date': Timestamp.fromDate(loanDate),
      'due_date': Timestamp.fromDate(dueDate),
      'bank_name': bankName,
      'account_number': accountNumber,
    };
  }
}