import 'package:cloud_firestore/cloud_firestore.dart';

class RequestModel {
  final String id;
  final double amount;
  final String category;
  final String description;
  final String targetWalletId;
  final String requesterId;
  final String requesterName;

  // [FIX] Kita gunakan branchId dan branchName agar jelas
  final String branchId;
  final String branchName;

  final String status;
  final DateTime createdAt;

  final double? approvedAmount;
  final DateTime? approvedAt;
  final String? approverId;
  final String? note;

  RequestModel({
    required this.id,
    required this.amount,
    required this.category,
    required this.description,
    required this.targetWalletId,
    required this.requesterId,
    required this.requesterName,
    // [FIX] Constructor diperbaiki
    required this.branchId,
    required this.branchName,

    required this.status,
    required this.createdAt,
    this.approvedAmount,
    this.approvedAt,
    this.approverId,
    this.note,
  });

  factory RequestModel.fromMap(Map<String, dynamic> map, String id) {
    return RequestModel(
      id: id,
      amount: (map['amount'] ?? 0).toDouble(),
      category: map['category'] ?? '',
      description: map['description'] ?? '',
      targetWalletId: map['target_wallet_id'] ?? '',
      requesterId: map['requester_id'] ?? '',
      requesterName: map['requester_name'] ?? '',

      // [FIX] Mapping dari Firestore (snake_case ke camelCase)
      branchId: map['branch_id'] ?? '',
      branchName: map['branch_name'] ?? 'Cabang Tidak Diketahui',

      status: map['status'] ?? 'pending',
      createdAt: (map['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      approvedAmount: (map['approved_amount'] as num?)?.toDouble(),
      approvedAt: (map['approved_at'] as Timestamp?)?.toDate(),
      approverId: map['approver_id'],
      note: map['note'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'amount': amount,
      'category': category,
      'description': description,
      'target_wallet_id': targetWalletId,
      'requester_id': requesterId,
      'requester_name': requesterName,

      // [FIX] Simpan ke Firestore
      'branch_id': branchId,
      'branch_name': branchName,

      'status': status,
      'created_at': Timestamp.fromDate(createdAt),
      'approved_amount': approvedAmount,
      'approved_at': approvedAt != null ? Timestamp.fromDate(approvedAt!) : null,
      'approver_id': approverId,
      'note': note,
    };
  }
}