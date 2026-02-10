import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

import '../../../models/wallet_model.dart';
import '../../../models/transaction_model.dart';
import '../../transactions/data/transaction_repository.dart';

// --- MODEL KHUSUS UNTUK GRAFIK ---
class DailySummary {
  final String dayLabel;
  final double income;
  final double expense;

  DailySummary(this.dayLabel, this.income, this.expense);
}

// --- STATES ---
abstract class DashboardState extends Equatable {
  @override
  List<Object> get props => [];
}

class DashboardInitial extends DashboardState {}
class DashboardLoading extends DashboardState {}

class DashboardLoaded extends DashboardState {
  final List<WalletModel> wallets;
  final double totalAssets;
  final List<TransactionModel> recentTransactions;
  final List<DailySummary> weeklyChartData;
  final double totalDebt;
  final List<Map<String, dynamic>> allDebts;

  DashboardLoaded({
    required this.wallets,
    required this.totalAssets,
    required this.recentTransactions,
    required this.weeklyChartData,
    required this.totalDebt,
    required this.allDebts,
  });

  @override
  List<Object> get props => [wallets, totalAssets, recentTransactions, weeklyChartData, totalDebt, allDebts];
}

class DashboardSuccess extends DashboardState {
  final String message;
  DashboardSuccess(this.message);

  @override
  List<Object> get props => [message];
}

class DashboardError extends DashboardState {
  final String message;
  DashboardError(this.message);

  @override
  List<Object> get props => [message];
}

// --- CUBIT (LOGIC UTAMA) ---
class DashboardCubit extends Cubit<DashboardState> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TransactionRepository _transactionRepository = TransactionRepository();

  StreamSubscription? _walletSub;
  StreamSubscription? _transactionSub;
  StreamSubscription? _debtSub;

  DashboardCubit() : super(DashboardInitial());

  void startMonitoring() {
    emit(DashboardLoading());

    // 1. Pantau Dompet
    _walletSub?.cancel();
    _walletSub = _firestore.collection('wallets').snapshots().listen((walletSnap) {
      _fetchRestOfData(walletSnap);
    }, onError: (e) => emit(DashboardError(e.toString())));
  }

  void _fetchRestOfData(QuerySnapshot walletSnap) {
    try {
      final wallets = walletSnap.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return WalletModel.fromMap(data, doc.id);
      }).toList();

      double totalAssets = wallets.fold(0, (sum, w) => sum + w.balance);

      // 2. Pantau Transaksi
      _transactionSub?.cancel();
      _transactionSub = _firestore.collection('transactions')
          .orderBy('date', descending: true)
          .limit(100)
          .snapshots()
          .listen((txSnap) {
        try {
          // Filter data: Hanya ambil yang deletedAt-nya NULL
          final transactions = txSnap.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return TransactionModel.fromMap(data, doc.id);
          }).where((tx) => tx.deletedAt == null).toList();

          // Data 'transactions' di atas sudah bersih
          final chartData = _calculateWeeklySummary(transactions);

          // 3. Pantau Utang
          _debtSub?.cancel();
          _debtSub = _firestore.collection('debts').snapshots().listen((debtSnap) {
            final allDebts = debtSnap.docs.map((d) {
              final data = d.data() as Map<String, dynamic>;
              data['id'] = d.id;
              return data;
            }).toList();

            double totalDebt = allDebts.fold(0.0, (sum, item) => sum + (item['amount'] ?? 0));

            // Emit Loaded State
            emit(DashboardLoaded(
              wallets: wallets,
              totalAssets: totalAssets,
              recentTransactions: transactions,
              weeklyChartData: chartData,
              totalDebt: totalDebt,
              allDebts: allDebts,
            ));
          }, onError: (e) {
            emit(DashboardError("Gagal memuat utang: $e"));
          });

        } catch (e) {
          emit(DashboardError("Data transaksi rusak: $e"));
        }
      }, onError: (e) {
        emit(DashboardError("Gagal memuat transaksi: $e"));
      });
    } catch (e) {
      emit(DashboardError("Gagal memuat dompet: $e"));
    }
  }

  List<DailySummary> _calculateWeeklySummary(List<TransactionModel> transactions) {
    List<DailySummary> summary = [];
    DateTime now = DateTime.now();
    for (int i = 6; i >= 0; i--) {
      DateTime targetDate = now.subtract(Duration(days: i));
      String dateKey = DateFormat('dd/MM').format(targetDate);
      var dailyTx = transactions.where((tx) {
        return DateFormat('dd/MM/yyyy').format(tx.date) == DateFormat('dd/MM/yyyy').format(targetDate);
      });

      double income = dailyTx.where((t) {
        return t.type == 'income' && !t.category.toLowerCase().contains('top up');
      }).fold(0, (sum, t) => sum + t.amount);

      double expense = dailyTx.where((t) {
        return t.type == 'expense' && !t.category.toLowerCase().contains('top up');
      }).fold(0, (sum, t) => sum + t.amount);

      summary.add(DailySummary(dateKey, income, expense));
    }
    return summary;
  }

  // [FIX] Terima Object TransactionModel (Smart Delete)
  Future<void> deleteTransaction(TransactionModel transaction) async {
    try {
      await _transactionRepository.deleteTransaction(transaction);
      emit(DashboardSuccess("Transaksi dihapus & Saldo dikembalikan"));
      startMonitoring(); // Refresh data
    } catch (e) {
      emit(DashboardError("Gagal menghapus: $e"));
      startMonitoring();
    }
  }

  // [FIX] Terima Object TransactionModel (Restore)
  Future<void> restoreTransaction(TransactionModel transaction) async {
    try {
      await _transactionRepository.restoreTransaction(transaction);
      emit(DashboardSuccess("Transaksi berhasil dipulihkan (Restore)!"));
      startMonitoring(); // Refresh data
    } catch (e) {
      emit(DashboardError("Gagal restore: $e"));
      startMonitoring();
    }
  }

  @override
  Future<void> close() {
    _walletSub?.cancel();
    _transactionSub?.cancel();
    _debtSub?.cancel();
    return super.close();
  }
}