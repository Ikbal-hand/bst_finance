import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionModel {
  final String id;
  final double amount;
  final String type; // 'income' atau 'expense'
  final String category;
  final String description;
  final String walletId;
  final DateTime date;
  final String userId;

  // Field Opsional / Tambahan
  final String? relatedBranchId;
  final String? relatedId; // ID Utang / Request
  final String? relatedType; // 'debt_payment', 'request_approval'
  final DateTime? deletedAt;

  // [FIX] Field Baru yang Menyebabkan Error
  final String status; // 'success', 'pending', 'deleted'
  final DateTime createdAt;

  TransactionModel({
    required this.id,
    required this.amount,
    required this.type,
    required this.category,
    required this.description,
    required this.walletId,
    required this.date,
    required this.userId,
    this.relatedBranchId,
    this.relatedId,
    this.relatedType,
    this.deletedAt,
    // Default value agar aman
    this.status = 'success',
    required this.createdAt,
  });

  factory TransactionModel.fromMap(Map<String, dynamic> map, String id) {
    return TransactionModel(
      id: id,
      amount: (map['amount'] ?? 0).toDouble(),
      type: map['type'] ?? 'expense',
      category: map['category'] ?? 'Umum',
      description: map['description'] ?? '',
      walletId: map['wallet_id'] ?? '',
      date: (map['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      userId: map['user_id'] ?? '',
      relatedBranchId: map['related_branch_id'],
      relatedId: map['related_id'],
      relatedType: map['related_type'],
      deletedAt: (map['deleted_at'] as Timestamp?)?.toDate(),
      // [FIX] Mapping Field Baru
      status: map['status'] ?? 'success',
      createdAt: (map['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'amount': amount,
      'type': type,
      'category': category,
      'description': description,
      'wallet_id': walletId,
      'date': Timestamp.fromDate(date),
      'user_id': userId,
      'related_branch_id': relatedBranchId,
      'related_id': relatedId,
      'related_type': relatedType,
      'deleted_at': deletedAt != null ? Timestamp.fromDate(deletedAt!) : null,
      // [FIX] Simpan Field Baru
      'status': status,
      'created_at': Timestamp.fromDate(createdAt),
    };
  }
}