import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

// --- IMPORTS LOGIC & MODEL ---
import '../../../core/services/notification_service.dart';
import '../../../core/services/fcm_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../models/wallet_model.dart';
import '../../../models/transaction_model.dart';
import '../../../core/constants/app_colors.dart';

// --- IMPORTS SCREEN LAIN ---
import '../../debts/presentation/debt_list_screen.dart';
import '../../notification/presentation/notification_screen.dart';
import '../../report/presentation/report_screen.dart';
import '../../settings/presentation/user_management_screen.dart';
import '../../transactions/presentation/add_transaction_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../employee/presentation/employee_list_screen.dart';
import '../../approval/presentation/approval_screen.dart';
import '../../report/presentation/monthly_report_screen.dart';
import '../../dashboard/presentation/transaction_history_screen.dart';
import '../../dashboard/presentation/wallet_detail_screen.dart';
import '../../transactions/data/transaction_repository.dart';
import '../logic/dashboard_cubit.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {

  // --- STATE USER & AKSES ---
  bool _isLoadingUser = true;
  String _userRole = '';
  String _userBranchId = '';
  String _selectedBranchId = 'pusat';

  // --- DATA TAB & CABANG (Untuk Owner) ---
  int _selectedTabIndex = 0;

  final List<String> _allTabs = ["Box Factory", "Maint. Alfa", "Saufa Olshop"];
  final List<String> _allBranchIds = ["bst_box", "m_alfa", "saufa"];
  // [UPDATE] ID Wallet sesuai Seeder Baru
  final List<String> _allWalletIds = ["petty_box", "petty_alfa", "petty_saufa"];

  List<String> _visibleTabs = [];
  List<String> _visibleBranchIds = [];
  List<String> _visibleWalletIds = [];
  StreamSubscription? _notifSubscription;

  @override
  void initState() {
    super.initState();
    NotificationService().init();
    FCMService().init();
    _checkUserAccess();
    _initData();
    context.read<DashboardCubit>().startMonitoring();
  }

  @override
  void dispose() {
    _notifSubscription?.cancel();
    super.dispose();
  }

  void _initData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && mounted) {
        setState(() {
          _userRole = doc['role'] ?? 'admin_branch';
          _userBranchId = doc['branch_id'] ?? 'bst_box';
        });
        _setupNotificationListener();
        _runDailyChecks(user.uid);
      }
    }
  }

  Future<void> _checkUserAccess() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() { _isLoadingUser = false; });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!doc.exists) {
        if (mounted) setState(() { _userRole = 'user'; _userBranchId = 'unknown'; _setupLimitedView(); _isLoadingUser = false; });
        return;
      }

      final data = doc.data()!;
      if (mounted) {
        setState(() {
          _userRole = data['role'] ?? 'admin_branch';
          _userBranchId = data['branch_id'] ?? 'bst_box';

          if (_userRole == 'owner') {
            _visibleTabs = List.from(_allTabs);
            _visibleBranchIds = List.from(_allBranchIds);
            _visibleWalletIds = List.from(_allWalletIds);
          } else {
            int index = _allBranchIds.indexOf(_userBranchId);
            if (index != -1) {
              _visibleTabs = [_allTabs[index]];
              _visibleBranchIds = [_allBranchIds[index]];
              _visibleWalletIds = [_allWalletIds[index]];
              _selectedBranchId = _userBranchId;
            } else {
              _setupLimitedView();
            }
          }
          _isLoadingUser = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _setupLimitedView(); _isLoadingUser = false; });
    }
  }

  void _setupLimitedView() {
    _visibleTabs = ["Akses Terbatas"];
    _visibleBranchIds = ["unknown"];
    _visibleWalletIds = ["unknown"];
  }

  Future<void> _onRefresh() async {
    context.read<DashboardCubit>().startMonitoring();
    await _checkUserAccess();
  }

  Future<void> _runDailyChecks(String userId) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayStr = DateFormat('yyyy-MM-dd').format(today);
    final userRef = FirebaseFirestore.instance.collection('users').doc(userId);

    final userDoc = await userRef.get();
    String lastCheck = userDoc.data()?['last_daily_check'] ?? '';

    if (lastCheck == todayStr) return;

    int paydayDay = 25; // Default tanggal gajian
    DateTime targetPayday = DateTime(today.year, today.month, paydayDay);
    if (targetPayday.isBefore(today)) {
      targetPayday = DateTime(today.year, today.month + 1, paydayDay);
    }
    int diffGaji = targetPayday.difference(today).inDays;
    if (diffGaji <= 3 && diffGaji >= 0) {
      String msg = diffGaji == 0 ? "Hari ini waktunya gajian!" : "Gajian tinggal $diffGaji hari lagi.";
      await _sendSystemNotification(title: "Reminder Penggajian 📅", message: msg, type: 'reminder_payroll');
    }

    await userRef.update({'last_daily_check': todayStr});
  }

  Future<void> _sendSystemNotification({required String title, required String message, required String type}) async {
    await FirebaseFirestore.instance.collection('notifications').add({
      'to_branch': _userBranchId,
      'title': title,
      'message': message,
      'type': type,
      'is_read': false,
      'date': FieldValue.serverTimestamp(),
    });
  }

  void _setupNotificationListener() {
    _notifSubscription?.cancel();
    Query query = FirebaseFirestore.instance.collection('notifications');

    if (_userRole == 'owner') {
      query = query.orderBy('date', descending: true).limit(10);
    } else {
      query = query.where('to_branch', whereIn: [_userBranchId, 'all']).orderBy('date', descending: true).limit(10);
    }

    _notifSubscription = query.snapshots().listen((snapshot) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingUser) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: Colors.white,
      drawer: _buildDrawer(context),
      appBar: AppBar(
        title: const Text("Dashboard", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .where('to_branch', whereIn: [_userRole == 'owner' ? 'owner' : _userBranchId, 'all'])
                .where('is_read', isEqualTo: false)
                .snapshots(),
            builder: (context, snapshot) {
              int unreadCount = 0;
              if (snapshot.hasData) {
                unreadCount = snapshot.data!.docs.length;
              }

              return IconButton(
                onPressed: () {
                  String targetBranch = _userRole == 'owner' ? 'owner' : _userBranchId;
                  Navigator.push(context, MaterialPageRoute(
                      builder: (c) => NotificationScreen(branchId: targetBranch)
                  ));
                },
                icon: Stack(
                  children: [
                    const Icon(Icons.notifications_outlined, color: Colors.black, size: 28),
                    if (unreadCount > 0)
                      Positioned(
                        right: 0, top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                          child: Center(
                            child: Text(
                              unreadCount > 9 ? '9+' : '$unreadCount',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      )
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 12),
        ],
      ),

      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: BlocBuilder<DashboardCubit, DashboardState>(
          builder: (context, state) {
            if (state is DashboardLoading) {
              return const Center(child: CircularProgressIndicator());
            } else if (state is DashboardError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 60, color: Colors.red),
                    Text("Error: ${state.message}"),
                    ElevatedButton(onPressed: () => context.read<DashboardCubit>().startMonitoring(), child: const Text("Coba Lagi"))
                  ],
                ),
              );
            } else if (state is DashboardLoaded) {
              if (state.wallets.isEmpty) {
                return Center(
                  child: ElevatedButton(
                    child: const Text("Generate 5 Wallet System"),
                    onPressed: () => _regenerateWallets(context),
                  ),
                );
              }

              // [LOGIC BARU] AMBIL DOMPET SPESIFIK 5 WALLET SYSTEM
              final companyWallet = state.wallets.firstWhere((w) => w.id == 'company_wallet', orElse: () => state.wallets.first);
              final treasurerWallet = state.wallets.firstWhere((w) => w.id == 'treasurer_wallet', orElse: () => WalletModel(id: 'null', name: 'N/A', balance: 0, branchId: '', isMain: false));

              // Hitung Total Kas Kecil Cabang (Level 3)
              final double totalBranchesCash = state.wallets
                  .where((w) => w.id != 'company_wallet' && w.id != 'treasurer_wallet')
                  .fold(0.0, (sum, w) => sum + w.balance);

              if (_selectedTabIndex >= _visibleBranchIds.length) _selectedTabIndex = 0;
              String currentBranch = _visibleBranchIds[_selectedTabIndex];
              String currentWalletId = _visibleWalletIds[_selectedTabIndex];
              _selectedBranchId = currentBranch;

              // Filter Transaksi untuk Grafik & List
              List<TransactionModel> filteredTransactions = state.recentTransactions.where((tx) {
                if (currentBranch == 'unknown') return false;
                // Tampilkan transaksi yg walletnya sesuai ATAU branch-nya sesuai
                bool isWalletMatch = tx.walletId == currentWalletId;
                bool isBranchMatch = (tx.relatedBranchId == currentBranch);
                return isWalletMatch || isBranchMatch;
              }).toList();

              List<DailySummary> filteredChartData = _recalculateChart(filteredTransactions);

              // Filter Utang
              List<Map<String, dynamic>> filteredDebts = state.allDebts.where((d) {
                return d['branch_id'] == currentBranch;
              }).toList();
              double currentTabDebt = filteredDebts.fold(0, (sum, d) => sum + (d['amount'] ?? 0));

              WalletModel? currentBranchWallet;
              try {
                currentBranchWallet = state.wallets.firstWhere((w) => w.branchId == currentBranch && w.id.startsWith('petty_'));
              } catch (_) {}

              double currentTabBalance = currentBranchWallet?.balance ?? 0;

              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- HEADER 3 LEVEL (KHUSUS OWNER) ---
                    if (_userRole == 'owner')
                      _buildOwnerHeader(companyWallet, treasurerWallet, totalBranchesCash)
                    else if (_userRole == 'admin_branch')
                      _buildBranchAdminHeader(currentBranchWallet, currentBranch)
                    else
                      _buildErrorHeader(),

                    const SizedBox(height: 20),

                    if (_userRole == 'owner') ...[
                      _buildCustomTabBar(),
                      const SizedBox(height: 20),
                    ],

                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Kartu Hijau (Saldo Kas Kecil Cabang)
                          if (_userRole == 'owner') ...[
                            Expanded(child: _buildGreenStatusCard(currentTabBalance, currentBranchWallet)),
                            const SizedBox(width: 12),
                          ],
                          // Kartu Merah (Utang Cabang)
                          Expanded(child: _buildDebtCard(currentTabDebt)),
                        ],
                      ),
                    ),

                    const SizedBox(height: 25),
                    Text("Ringkasan ${_visibleTabs.isNotEmpty ? _visibleTabs[_selectedTabIndex] : '-'}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 15),
                    _buildChartContainer(filteredChartData),

                    const SizedBox(height: 25),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Transaksi Terkini", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        TextButton(onPressed: (){
                          Navigator.push(context, MaterialPageRoute(builder: (c) => const TransactionHistoryScreen()));
                        }, child: Text("Lihat Semua", style: TextStyle(color: Colors.grey[400])))
                      ],
                    ),
                    const SizedBox(height: 10),

                    if (filteredTransactions.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        width: double.infinity,
                        decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12)),
                        child: const Center(child: Text("Belum ada transaksi")),
                      )
                    else
                      ...filteredTransactions.take(5).map((tx) => _buildTransactionItem(tx)),

                    const SizedBox(height: 80),
                  ],
                ),
              );
            }
            return const SizedBox();
          },
        ),
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AddTransactionScreen())),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  // --- [HEADER BARU] 3 LEVEL HIERARKI KEUANGAN ---
  Widget _buildOwnerHeader(WalletModel companyWallet, WalletModel treasurerWallet, double totalBranches) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1565C0), Color(0xFF1E88E5)], // Biru Profesional
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))
          ]
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // LEVEL 1: UANG PERUSAHAAN
            InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => WalletDetailScreen(wallet: companyWallet))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                    child: const Icon(Icons.business, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("UANG PERUSAHAAN (Level 1)", style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 10, letterSpacing: 1)),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(_formatRupiah(companyWallet.balance), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Divider(color: Colors.white24, height: 1),
            ),

            // LEVEL 2 & 3: BENDAHARA & CABANG
            IntrinsicHeight(
              child: Row(
                children: [
                  // LEVEL 2: KAS BENDAHARA
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => WalletDetailScreen(wallet: treasurerWallet))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.account_balance, color: Colors.white70, size: 14),
                              const SizedBox(width: 4),
                              Expanded(child: Text("Bendahara Pusat", style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 11, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(_formatRupiah(treasurerWallet.balance), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))
                          ),
                          // [BARU] TOMBOL ISI MODAL BENDAHARA
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () => _showTopUpTreasurerDialog(companyWallet, treasurerWallet),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_circle, color: Color(0xFF1565C0), size: 12),
                                  SizedBox(width: 4),
                                  Text("Isi Modal", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1565C0))),
                                ],
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),

                  VerticalDivider(color: Colors.white.withOpacity(0.3), width: 20),

                  // LEVEL 3: TOTAL CABANG
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.store, color: Colors.white70, size: 14),
                            const SizedBox(width: 4),
                            Expanded(child: Text("Total Kas Cabang", style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 11, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(_formatRupiah(totalBranches), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          ]
      ),
    );
  }

  // LOGIC: ISI MODAL BENDAHARA (Level 1 -> Level 2)
  void _showTopUpTreasurerDialog(WalletModel companyWallet, WalletModel treasurerWallet) {
    final nominalCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Isi Modal Bendahara"),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
                child: const Text(
                  "Ambil dana dari UANG PERUSAHAAN (Level 1) ke KAS BENDAHARA (Level 2).",
                  style: TextStyle(fontSize: 12, color: Colors.blue),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                  controller: nominalCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Nominal (Rp)", border: OutlineInputBorder(), prefixText: "Rp ")
              )
            ]
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[800]),
            onPressed: () async {
              if (nominalCtrl.text.isEmpty) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Memproses...")));

              try {
                double amount = double.parse(nominalCtrl.text.replaceAll('.', ''));
                if (companyWallet.balance < amount) throw Exception("Saldo Uang Perusahaan tidak cukup!");

                await FirebaseFirestore.instance.runTransaction((tx) async {
                  final compRef = FirebaseFirestore.instance.collection('wallets').doc(companyWallet.id);
                  final treasRef = FirebaseFirestore.instance.collection('wallets').doc(treasurerWallet.id);

                  final compSnap = await tx.get(compRef);
                  final treasSnap = await tx.get(treasRef);

                  double bal1 = (compSnap.get('balance') ?? 0).toDouble();
                  double bal2 = (treasSnap.get('balance') ?? 0).toDouble();

                  tx.update(compRef, {'balance': bal1 - amount});
                  tx.update(treasRef, {'balance': bal2 + amount});

                  // Catat Mutasi
                  tx.set(FirebaseFirestore.instance.collection('transactions').doc(), {
                    'amount': amount, 'type': 'expense', 'category': 'Mutasi Internal', 'description': 'Mutasi ke Kas Bendahara', 'wallet_id': companyWallet.id, 'date': FieldValue.serverTimestamp(), 'user_id': FirebaseAuth.instance.currentUser?.uid, 'deleted_at': null
                  });
                  tx.set(FirebaseFirestore.instance.collection('transactions').doc(), {
                    'amount': amount, 'type': 'income', 'category': 'Suntikan Modal Internal', 'description': 'Terima Modal dari Perusahaan', 'wallet_id': treasurerWallet.id, 'date': FieldValue.serverTimestamp(), 'user_id': FirebaseAuth.instance.currentUser?.uid, 'deleted_at': null
                  });
                });
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Modal Bendahara Terisi!"), backgroundColor: Colors.green));
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: ${e.toString()}"), backgroundColor: Colors.red));
              }
            },
            child: const Text("Isi Modal"),
          )
        ],
      ),
    );
  }

  Widget _buildBranchAdminHeader(WalletModel? wallet, String branchId) {
    double balance = wallet?.balance ?? 0;
    return GestureDetector(
      onTap: () { if (wallet != null) Navigator.push(context, MaterialPageRoute(builder: (c) => WalletDetailScreen(wallet: wallet))); },
      child: Container(width: double.infinity, padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: AppColors.branchBst, gradient: LinearGradient(colors: branchId == 'bst_box' ? [const Color(0xFFD97706), const Color(0xFFF59E0B)] : branchId == 'm_alfa' ? [const Color(0xFFDC2626), const Color(0xFFEF4444)] : [const Color(0xFF7C3AED), const Color(0xFF8B5CF6)]), borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const Icon(Icons.store, color: Colors.white70, size: 18), const SizedBox(width: 8), Text("Kas Harian: ${branchId.toUpperCase().replaceAll('_', ' ')}", style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14))]), const SizedBox(height: 12), Text(_formatRupiah(balance), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)), child: const Text("Level 3 Access", style: TextStyle(color: Colors.white, fontSize: 10)))])),
    );
  }

  Widget _buildErrorHeader() {
    return Container(width: double.infinity, padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(24)), child: const Text("Akses tidak valid.", style: TextStyle(color: Colors.white)));
  }
  // Tambahkan fungsi ini di dalam class _DashboardScreenState
  String _getBranchName(String? branchId) {
    if (branchId == null) return 'Pusat';
    switch (branchId) {
      case 'bst_box': return 'Box Factory';
      case 'm_alfa': return 'Maint. Alfa';
      case 'saufa': return 'Saufa Olshop';
      case 'pusat': return 'Kantor Pusat';
      default: return 'Cabang Lain';
    }
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // --- HEADER USER ---
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: AppColors.primary),
            accountName: Text(_userRole == 'owner' ? "Owner / Pusat" : "Admin Cabang"),
            accountEmail: Text(_userRole == 'owner' ? "Pusat Control" : _getBranchName(_userBranchId)),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(
                _userRole == 'owner' ? Icons.admin_panel_settings : Icons.person,
                color: AppColors.primary,
                size: 32,
              ),
            ),
          ),

          // --- MENU UTAMA ---
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text('Dashboard'),
            onTap: () => Navigator.pop(context),
          ),

          ListTile(
            leading: const Icon(Icons.analytics_outlined, color: Colors.blue),
            title: const Text("Laporan Keuangan"),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ReportScreen())
              );
            },
          ),

          ListTile(
            leading: const Icon(Icons.monetization_on_outlined, color: Colors.redAccent),
            title: const Text('Utang Usaha'),
            onTap: () {
              Navigator.pop(context);
              // Jika Owner: Lihat utang sesuai filter dashboard.
              // Jika Admin: Lihat utang cabang sendiri.
              String targetBranch = _userRole == 'owner' ? _selectedBranchId : _userBranchId;
              Navigator.push(context, MaterialPageRoute(builder: (c) => DebtListScreen(branchId: targetBranch)));
            },
          ),

          ListTile(
            leading: const Icon(Icons.people_outline),
            title: const Text('Manajemen Pegawai'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (c) => EmployeeListScreen(branchId: _userBranchId)));
            },
          ),

          // --- MENU KHUSUS OWNER ---
          if (_userRole == 'owner') ...[
            const Divider(thickness: 1),
            const Padding(
              padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
              child: Text("Menu Owner", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
            ),

            ListTile(
              leading: const Icon(Icons.verified_user, color: Colors.green),
              title: const Text('Persetujuan (Approval)'),
              trailing: const Icon(Icons.chevron_right, size: 16),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (c) => const ApprovalScreen()));
              },
            ),

            ListTile(
              leading: const Icon(Icons.manage_accounts, color: Colors.purple),
              title: const Text('Manajemen User Akses'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (c) => const UserManagementScreen()));
              },
            ),
          ],

          const Divider(thickness: 1),

          // --- PENGATURAN ---
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Pengaturan'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (c) => const SettingsScreen()));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCustomTabBar() {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(_visibleTabs.length, (index) { final isSelected = _selectedTabIndex == index; return GestureDetector(onTap: () => setState(() => _selectedTabIndex = index), child: Column(children: [Text(_visibleTabs[index], style: TextStyle(color: isSelected ? AppColors.primary : Colors.grey[400], fontWeight: FontWeight.bold, fontSize: 14)), const SizedBox(height: 8), Container(height: 3, width: 40, decoration: BoxDecoration(color: isSelected ? AppColors.primary : Colors.transparent, borderRadius: BorderRadius.circular(2)))])); }));
  }

  Widget _buildChartContainer(List<DailySummary> chartData) {
    if (chartData.isEmpty) return const SizedBox(height: 200, child: Center(child: Text("Menunggu data...")));
    return Container(
        height: 250, padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade100)),
        child: BarChart(
            BarChartData(
                titlesData: FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (val, meta) { int idx = val.toInt(); if(idx >= 0 && idx < chartData.length) return Padding(padding: const EdgeInsets.only(top: 8), child: Text(chartData[idx].dayLabel, style: const TextStyle(fontSize: 10, color: Colors.grey))); return const Text(""); }))
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: chartData.asMap().entries.map((e) => BarChartGroupData(x: e.key, barRods: [
                  BarChartRodData(toY: e.value.income, color: AppColors.success, width: 8, borderRadius: BorderRadius.circular(4)),
                  BarChartRodData(toY: e.value.expense, color: AppColors.error, width: 8, borderRadius: BorderRadius.circular(4))
                ])).toList()
            )
        )
    );
  }

  List<DailySummary> _recalculateChart(List<TransactionModel> txs) {
    List<DailySummary> summary = [];
    DateTime now = DateTime.now();

    for (int i = 6; i >= 0; i--) {
      DateTime targetDate = now.subtract(Duration(days: i));
      String dayLabel = DateFormat('E', 'id_ID').format(targetDate);

      // Ambil transaksi hari tersebut
      var dailyTx = txs.where((tx) =>
      tx.date.day == targetDate.day &&
          tx.date.month == targetDate.month &&
          tx.date.year == targetDate.year
      );

      // --- LOGIC FILTER BARU ---
      // Kita abaikan kategori yang mengandung kata "Top Up", "Mutasi", atau "Internal"
      // agar tidak dianggap sebagai Pemasukan/Pengeluaran Real.

      double income = dailyTx.where((t) {
        bool isTransfer = t.category.contains('Top Up') ||
            t.category.contains('Mutasi') ||
            t.category.contains('Internal');
        return t.type == 'income' && !isTransfer;
      }).fold(0, (sum, t) => sum + t.amount);

      double expense = dailyTx.where((t) {
        bool isTransfer = t.category.contains('Top Up') ||
            t.category.contains('Mutasi') ||
            t.category.contains('Internal');
        return t.type == 'expense' && !isTransfer;
      }).fold(0, (sum, t) => sum + t.amount);

      summary.add(DailySummary(dayLabel, income, expense));
    }
    return summary;
  }

  Widget _buildTransactionItem(TransactionModel tx) {
    bool isIncome = tx.type == 'income';
    return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(12)), child: Row(children: [Icon(isIncome ? Icons.arrow_downward : Icons.arrow_upward, color: isIncome ? Colors.green : Colors.red), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tx.description.isNotEmpty ? tx.description : tx.category, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)), Text(DateFormat('dd MMM').format(tx.date), style: const TextStyle(fontSize: 10, color: Colors.grey))])), Text((isIncome?"+ ":"- ") + _formatRupiah(tx.amount), style: TextStyle(fontWeight: FontWeight.bold, color: isIncome ? Colors.green : Colors.red))]));
  }

  Widget _buildGreenStatusCard(double amount, WalletModel? wallet) {
    return GestureDetector(
      onTap: () { if (wallet != null) Navigator.push(context, MaterialPageRoute(builder: (c) => WalletDetailScreen(wallet: wallet))); },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.greenSoft, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.greenText.withOpacity(0.1))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(children: [Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: const Icon(Icons.account_balance_wallet, color: AppColors.greenText, size: 16)), const SizedBox(width: 8), const Expanded(child: Text("Sisa Kas Kecil", maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.greenText, fontSize: 12, fontWeight: FontWeight.bold)))]),
                  const SizedBox(height: 12),
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(wallet == null ? "Belum Aktif" : _formatRupiah(amount), style: const TextStyle(color: AppColors.greenText, fontWeight: FontWeight.bold, fontSize: 22))),
                  const SizedBox(height: 4),
                  Text(wallet == null ? "Tap tombol di kanan ->" : "Level 3", style: const TextStyle(color: Colors.grey, fontSize: 10)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Material(
                color: Colors.white, borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => wallet != null
                      ? _showTopUpDialog(wallet) // Top Up dari Bendahara
                      : _createMissingWallet(_visibleBranchIds[_selectedTabIndex]),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(border: Border.all(color: AppColors.greenText.withOpacity(0.2)), borderRadius: BorderRadius.circular(12)),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(wallet != null ? Icons.add_circle : Icons.build_circle, color: AppColors.greenText, size: 24),
                          const SizedBox(height: 2),
                          Text(wallet != null ? "Top Up" : "Aktifkan", style: const TextStyle(color: AppColors.greenText, fontWeight: FontWeight.bold, fontSize: 9))
                        ]
                    ),
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDebtCard(double totalDebt) {
    return GestureDetector(
      onTap: () => _showDebtListModal(context),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.redSoft, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.error.withOpacity(0.1))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(children: [Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: const Icon(Icons.receipt_long, color: AppColors.error, size: 16)), const SizedBox(width: 10), Text("Total Utang", style: TextStyle(color: AppColors.error.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.bold))]),
          const SizedBox(height: 12),
          Text(_formatRupiah(totalDebt), style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 22)),
          const SizedBox(height: 4),
          const Text("Tap untuk detail >", style: TextStyle(color: Colors.grey, fontSize: 11)),
        ]),
      ),
    );
  }

  // --- LOGIC TOP UP: DARI KAS BENDAHARA KE CABANG ---
  void _showTopUpDialog(WalletModel targetWallet) {
    final nominalCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Top Up: ${targetWallet.name}"),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.orange[50],
                child: const Text("⚠️ Dana akan diambil dari KAS BENDAHARA PUSAT (Level 2).", style: TextStyle(fontSize: 12, color: Colors.deepOrange)),
              ),
              const SizedBox(height: 16),
              TextField(
                  controller: nominalCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Nominal (Rp)", border: OutlineInputBorder(), prefixText: "Rp ")
              )
            ]
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () async {
              if (nominalCtrl.text.isEmpty) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Memproses Top Up...")));

              try {
                double amount = double.parse(nominalCtrl.text.replaceAll('.', ''));
                String walletSumber = 'treasurer_wallet'; // [FIX] Sumber dari Bendahara
                String walletCabang = targetWallet.id;

                await FirebaseFirestore.instance.runTransaction((tx) async {
                  // A. Cek Saldo Bendahara
                  final sumberSnap = await tx.get(FirebaseFirestore.instance.collection('wallets').doc(walletSumber));
                  if (!sumberSnap.exists) throw Exception("Dompet Bendahara Pusat belum aktif!");

                  double saldoSumber = (sumberSnap.get('balance') ?? 0).toDouble();
                  if (saldoSumber < amount) {
                    throw Exception("Saldo Bendahara Pusat tidak cukup! (Sisa: ${_formatRupiah(saldoSumber)})");
                  }

                  final cabangSnap = await tx.get(FirebaseFirestore.instance.collection('wallets').doc(walletCabang));
                  if (!cabangSnap.exists) throw Exception("Dompet cabang tidak ditemukan!");

                  // B. Buat Transaksi
                  // 1. Pengeluaran Bendahara
                  final txSumberRef = FirebaseFirestore.instance.collection('transactions').doc();
                  tx.set(txSumberRef, {
                    'amount': amount,
                    'type': 'expense',
                    'category': 'Top Up Cabang',
                    'description': 'Top Up ke ${targetWallet.name}',
                    'wallet_id': walletSumber,
                    'related_branch_id': targetWallet.branchId,
                    'date': FieldValue.serverTimestamp(),
                    'user_id': _userRole == 'owner' ? 'owner' : _userBranchId,
                    'deleted_at': null
                  });

                  // 2. Pemasukan Cabang
                  final txCabangRef = FirebaseFirestore.instance.collection('transactions').doc();
                  tx.set(txCabangRef, {
                    'amount': amount,
                    'type': 'income',
                    'category': 'Top Up Masuk',
                    'description': 'Terima dari Bendahara Pusat',
                    'wallet_id': walletCabang,
                    'related_branch_id': targetWallet.branchId,
                    'date': FieldValue.serverTimestamp(),
                    'user_id': _userRole == 'owner' ? 'owner' : _userBranchId,
                    'deleted_at': null
                  });

                  // C. Update Saldo
                  double saldoCabang = (cabangSnap.get('balance') ?? 0).toDouble();
                  tx.update(sumberSnap.reference, {'balance': saldoSumber - amount});
                  tx.update(cabangSnap.reference, {'balance': saldoCabang + amount});
                });

                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Top Up Berhasil!"), backgroundColor: Colors.green));
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: ${e.toString().replaceAll('Exception:', '')}"), backgroundColor: Colors.red));
              }
            },
            child: const Text("Kirim Dana"),
          )
        ],
      ),
    );
  }

  void _showDebtListModal(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(
        builder: (c) => DebtListScreen(branchId: _selectedBranchId)
    ));
  }

  String _formatRupiah(double amount) => NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(amount);

  // --- REGENERATE SESUAI 5 WALLET SYSTEM ---
  void _regenerateWallets(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sedang membuat ulang sistem 5 dompet...")));
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();

    // Level 1 & 2
    batch.set(firestore.collection('wallets').doc('company_wallet'), {'name': 'Uang Perusahaan', 'branch_id': 'pusat', 'balance': 0, 'level': 1, 'is_main': true});
    batch.set(firestore.collection('wallets').doc('treasurer_wallet'), {'name': 'Kas Bendahara Pusat', 'branch_id': 'pusat', 'balance': 0, 'level': 2, 'is_main': false});

    // Level 3
    batch.set(firestore.collection('wallets').doc('petty_box'), {'name': 'Kas Harian Box', 'branch_id': 'bst_box', 'balance': 0, 'level': 3, 'is_main': false});
    batch.set(firestore.collection('wallets').doc('petty_alfa'), {'name': 'Kas Harian Alfa', 'branch_id': 'm_alfa', 'balance': 0, 'level': 3, 'is_main': false});
    batch.set(firestore.collection('wallets').doc('petty_saufa'), {'name': 'Kas Harian Saufa', 'branch_id': 'saufa', 'balance': 0, 'level': 3, 'is_main': false});

    try {
      await batch.commit();
      if (mounted) {
        context.read<DashboardCubit>().startMonitoring();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Berhasil! Sistem dompet dipulihkan.")));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e")));
    }
  }

  // --- CREATE MISSING SESUAI ID BARU ---
  Future<void> _createMissingWallet(String branchId) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mengaktifkan dompet...")));
    String walletId = '';
    String walletName = '';

    if (branchId == 'm_alfa') {
      walletId = 'petty_alfa';
      walletName = 'Kas Harian Alfa';
    } else if (branchId == 'saufa') {
      walletId = 'petty_saufa';
      walletName = 'Kas Harian Saufa';
    } else if (branchId == 'bst_box') {
      walletId = 'petty_box';
      walletName = 'Kas Harian Box';
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cabang tidak dikenali")));
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('wallets').doc(walletId).set({
        'name': walletName,
        'branch_id': branchId,
        'balance': 0,
        'level': 3,
        'is_main': false,
      });

      if (mounted) {
        context.read<DashboardCubit>().startMonitoring();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Dompet Berhasil Diaktifkan!"), backgroundColor: Colors.green));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e")));
    }
  }
}