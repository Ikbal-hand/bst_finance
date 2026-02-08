import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../models/transaction_model.dart';

class AddTransactionScreen extends StatefulWidget {
  final String? branchId;
  final TransactionModel? transactionToEdit;

  const AddTransactionScreen({super.key, this.branchId, this.transactionToEdit});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _ItemController {
  final Key key = UniqueKey();

  TextEditingController name = TextEditingController();
  TextEditingController unit = TextEditingController();
  TextEditingController qty = TextEditingController(text: '1');
  TextEditingController price = TextEditingController();

  void dispose() {
    name.dispose();
    unit.dispose();
    qty.dispose();
    price.dispose();
  }
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- CONFIG ---
  final String _companyWalletId = 'company_wallet';     // Level 1
  final String _treasurerWalletId = 'treasurer_wallet'; // Level 2

  // --- STATE USER ---
  String _userRole = 'admin_branch';
  String _userBranchId = '';
  String _userName = '';
  bool _isLoading = false;

  // --- STATE UI ---
  bool _isIncome = false;
  String? _selectedBranchId;
  String? _selectedWalletId;
  DateTime _selectedDate = DateTime.now();
  String _transactionDateStr = DateFormat('dd MMMM yyyy', 'id_ID').format(DateTime.now());

  // --- KATEGORI ---
  String? _selectedCategory;
  final TextEditingController _customCategoryCtrl = TextEditingController();
  final TextEditingController _capitalAmountCtrl = TextEditingController();

  final List<String> _incomeCategories = ['Penjualan', 'Jasa', 'Lainnya'];
  final List<String> _expenseCategories = ['Harian', 'Belanja Perusahaan', 'Beban Perusahaan', 'Maintenance', 'Gaji', 'Lainnya'];

  // --- ITEMS ---
  List<_ItemController> _items = [];
  double _totalEstimated = 0;

  @override
  void initState() {
    super.initState();
    _initUserAndData();
    _addItem();
  }

  @override
  void dispose() {
    for (var i in _items) i.dispose();
    _customCategoryCtrl.dispose();
    _capitalAmountCtrl.dispose();
    super.dispose();
  }

  void _initUserAndData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists && mounted) {
        setState(() {
          _userRole = doc['role'] ?? 'admin_branch';
          _userBranchId = doc['branch_id'] ?? 'bst_box';
          _userName = doc['name'] ?? 'Admin';

          if (_userRole == 'owner') {
            _selectedBranchId = widget.branchId ?? 'bst_box';
            if (!_incomeCategories.contains('Suntikan Modal')) {
              _incomeCategories.insert(0, 'Suntikan Modal');
            }
          } else {
            _selectedBranchId = _userBranchId;
          }

          _selectedCategory = _isIncome ? _incomeCategories.first : 'Harian';
          _updateAutoWalletLogic();
        });
      }
    }
  }

  // --- LOGIC UTAMA: AUTO SELECT WALLET ---

  void _updateAutoWalletLogic() {
    if (_selectedBranchId == null && _selectedCategory != 'Suntikan Modal') return;

    setState(() {
      if (_isIncome) {
        // PEMASUKAN
        if (_selectedCategory == 'Suntikan Modal' && _userRole == 'owner') {
          _selectedWalletId = _treasurerWalletId;
        } else {
          _selectedWalletId = _companyWalletId;
        }
      } else {
        // PENGELUARAN
        if (_selectedCategory == 'Harian') {
          // Kategori Harian -> Selalu pakai Kas Kecil Cabang (Langsung Cair)
          _selectedWalletId = _getBranchWalletId(_selectedBranchId!);
        } else {
          // Non-Harian (Belanja Pusat/Gaji) -> Tembak ke Kas Bendahara Pusat
          // (Akan jadi Request Approval jika user bukan Owner)
          _selectedWalletId = _treasurerWalletId;
        }
      }
    });
  }

  // Cek apakah transaksi ini butuh Approval Owner?
  bool _needsApproval() {
    // Owner = Bebas (Langsung Cair)
    if (_userRole == 'owner') return false;

    // Admin Cabang:
    if (_isIncome) return false; // Pemasukan langsung masuk
    if (_selectedCategory == 'Harian') return false; // Kas Kecil langsung cair

    // Sisanya (Belanja Pusat/Gaji/Maintenance) -> BUTUH APPROVAL
    return true;
  }

  String _getBranchWalletId(String branchId) {
    switch (branchId) {
      case 'm_alfa': return 'petty_alfa';
      case 'saufa': return 'petty_saufa';
      case 'bst_box': return 'petty_box';
      default: return 'petty_box';
    }
  }

  String _getBranchName(String branchId) {
    switch (branchId) {
      case 'm_alfa': return 'Maint. Alfa';
      case 'saufa': return 'Saufa Olshop';
      case 'bst_box': return 'Box Factory';
      case 'pusat': return 'Kantor Pusat';
      default: return 'Cabang Lain';
    }
  }

  String _getWalletNameDisplay() {
    if (_selectedWalletId == _companyWalletId) return "Uang Perusahaan (Pusat)";
    if (_selectedWalletId == _treasurerWalletId) return "Kas Bendahara Pusat";
    if (_selectedWalletId != null && _selectedWalletId!.startsWith('petty_')) {
      String cabang = _selectedBranchId?.replaceAll('_', ' ').toUpperCase() ?? 'CABANG';
      return "Kas Kecil ($cabang)";
    }
    return "Kas Kecil Cabang";
  }

  void _calculateTotal() {
    double total = 0;
    if (_isIncome && _selectedCategory == 'Suntikan Modal') {
      total = double.tryParse(_capitalAmountCtrl.text.replaceAll('.', '')) ?? 0;
    } else {
      for (var item in _items) {
        double price = double.tryParse(item.price.text.replaceAll('.', '')) ?? 0;
        int qty = int.tryParse(item.qty.text) ?? 1;
        total += (price * qty);
      }
    }
    if (mounted) setState(() => _totalEstimated = total);
  }

  // --- SUBMIT TRANSACTION (CORE LOGIC) ---
  Future<void> _submitTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    if (_totalEstimated <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Total nominal tidak boleh 0")));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      bool needApproval = _needsApproval(); // Cek logic approval

      bool isSuntikModal = _isIncome && _selectedCategory == 'Suntikan Modal';

      // 1. Siapkan Deskripsi & Data
      String description = "";
      String mainItemName = ""; // Untuk judul notifikasi/request

      if (isSuntikModal) {
        description = "Suntikan Modal (Ke: ${_selectedWalletId == _companyWalletId ? 'Uang Perusahaan' : 'Kas Bendahara'})";
        mainItemName = "Suntikan Modal";
      } else {
        // Ambil item pertama sebagai judul utama
        mainItemName = _items.isNotEmpty ? _items.first.name.text : "Barang";
        if (_items.length > 1) mainItemName += " (+${_items.length - 1} lainnya)";

        description = _items.map((e) {
          String priceFmt = NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(double.tryParse(e.price.text.replaceAll('.', '')) ?? 0);
          return "${e.name.text} (${e.qty.text} ${e.unit.text} @ $priceFmt)";
        }).join(", ");
        description += " (Oleh: $_userName)";
      }

      String finalCategory = _selectedCategory ?? 'Umum';
      if (finalCategory == 'Lainnya' && _customCategoryCtrl.text.isNotEmpty) {
        finalCategory = _customCategoryCtrl.text;
      }

      String? finalBranchId = isSuntikModal ? 'pusat' : _selectedBranchId;

      // ---------------------------------------------------------
      // SKENARIO A: BUTUH APPROVAL (Masuk ke Request & Notifikasi)
      // ---------------------------------------------------------
      if (needApproval) {
        // Buat Request Baru
        await _firestore.collection('requests').add({
          'amount': _totalEstimated,
          'category': finalCategory,
          'item_name': mainItemName, // Judul item
          'description': description, // Detail lengkap
          'branch_id': finalBranchId,
          'branch_name': _getBranchName(finalBranchId ?? ''),
          'requester_id': user?.uid,
          'requester_name': _userName,
          'status': 'pending',
          'created_at': FieldValue.serverTimestamp(),
          'wallet_id': _selectedWalletId, // Target wallet (Bendahara)
          'note': 'Menunggu persetujuan Owner',
        });

        // Kirim Notifikasi ke Owner
        await _firestore.collection('notifications').add({
          'to_branch': 'owner', // Kirim ke Owner
          'title': 'Permintaan Dana Baru',
          'message': '$_userName mengajukan ${_formatRupiah(_totalEstimated)} untuk $finalCategory ($mainItemName)',
          'type': 'request_new',
          'is_read': false,
          'date': FieldValue.serverTimestamp(),
        });

      }
      // ---------------------------------------------------------
      // SKENARIO B: LANGSUNG CAIR (Transaksi Normal)
      // ---------------------------------------------------------
      else {
        Map<String, dynamic> txData = {
          'amount': _totalEstimated,
          'type': _isIncome ? 'income' : 'expense',
          'category': finalCategory,
          'description': description,
          'wallet_id': _selectedWalletId,
          'date': _selectedDate,
          'user_id': user?.uid ?? 'unknown',
          'related_branch_id': finalBranchId,
          'status': 'success',
          'created_at': FieldValue.serverTimestamp(),
          'deleted_at': null,
        };

        await _firestore.runTransaction((tx) async {
          final walletRef = _firestore.collection('wallets').doc(_selectedWalletId);
          final walletSnap = await tx.get(walletRef);

          if (!walletSnap.exists) throw Exception("Dompet tujuan tidak ditemukan!");

          double currentBalance = (walletSnap.data()?['balance'] ?? 0).toDouble();

          if (!_isIncome && currentBalance < _totalEstimated) {
            throw Exception("Saldo tidak cukup! Sisa: ${_formatRupiah(currentBalance)}");
          }

          double newBalance = _isIncome
              ? currentBalance + _totalEstimated
              : currentBalance - _totalEstimated;

          tx.update(walletRef, {'balance': newBalance});

          final newTxRef = _firestore.collection('transactions').doc();
          tx.set(newTxRef, txData);
        });
      }

      if (mounted) {
        String msg = needApproval
            ? "Permintaan Terkirim! Menunggu Approval Owner."
            : "Transaksi Berhasil Disimpan!";

        Color snackColor = needApproval ? Colors.orange[800]! : Colors.green;

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: snackColor));
        Navigator.pop(context);
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: ${e.toString().replaceAll('Exception:', '')}"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatRupiah(double amount) => NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(amount);

  // --- UI BUILDER ---

  @override
  Widget build(BuildContext context) {
    bool isSuntikModal = _isIncome && _selectedCategory == 'Suntikan Modal';
    bool isPending = _needsApproval(); // Cek status untuk UI

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("Catat Transaksi", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w700, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black54),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildModernToggle(),
                    const SizedBox(height: 24),

                    _buildFormCard(isSuntikModal),

                    // ALERT APPROVAL (Jika status pending)
                    if (isPending)
                      Container(
                        margin: const EdgeInsets.only(top: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.withOpacity(0.3))),
                        child: Row(
                          children: const [
                            Icon(Icons.access_time_filled, size: 24, color: Colors.orange),
                            SizedBox(width: 12),
                            Expanded(child: Text("Transaksi ini menggunakan Kas Bendahara Pusat, sehingga memerlukan Approval dari Owner.", style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold))),
                          ],
                        ),
                      )
                  ],
                ),
              ),
            ),
          ),

          _buildBottomActionBar(isPending),
        ],
      ),
    );
  }

  Widget _buildModernToggle() {
    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(25)),
      child: Row(
        children: [
          Expanded(child: _toggleItem("Pengeluaran", false)),
          Expanded(child: _toggleItem("Pemasukan", true)),
        ],
      ),
    );
  }

  Widget _toggleItem(String label, bool isIncome) {
    bool selected = _isIncome == isIncome;
    return GestureDetector(
      onTap: () {
        setState(() {
          _isIncome = isIncome;
          _selectedCategory = isIncome ? _incomeCategories.first : 'Harian'; // Default Harian saat switch ke Pengeluaran
          _updateAutoWalletLogic();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          boxShadow: selected ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))] : [],
        ),
        child: Text(
          label,
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: selected ? (isIncome ? AppColors.success : AppColors.error) : Colors.grey[600],
              fontSize: 14
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard(bool isSuntikModal) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_isIncome ? Icons.savings_outlined : Icons.account_balance_wallet_outlined, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                _isIncome ? "Masuk ke: " : "Sumber Dana: ",
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              Expanded(
                child: Text(
                  _getWalletNameDisplay(),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Divider(height: 30),

          _buildDropdowns(isSuntikModal),
          const SizedBox(height: 20),

          if (isSuntikModal) ...[
            _buildSuntikModalForm(),
          ] else ...[
            _buildItemList(),
          ]
        ],
      ),
    );
  }

  Widget _buildDropdowns(bool isSuntikModal) {
    bool showBranchDropdown = _userRole == 'owner' && !isSuntikModal;

    return Row(
      children: [
        if (showBranchDropdown) ...[
          Expanded(
            flex: 4,
            child: _modernDropdown(
              label: "Cabang",
              value: _selectedBranchId,
              items: const [
                DropdownMenuItem(value: 'bst_box', child: Text("Box Factory")),
                DropdownMenuItem(value: 'm_alfa', child: Text("Maint. Alfa")),
                DropdownMenuItem(value: 'saufa', child: Text("Saufa Olshop")),
              ],
              onChanged: (val) {
                setState(() {
                  _selectedBranchId = val;
                  _updateAutoWalletLogic();
                });
              },
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          flex: showBranchDropdown ? 6 : 1,
          child: _modernDropdown(
            label: "Kategori",
            value: _selectedCategory,
            items: (_isIncome ? _incomeCategories : _expenseCategories)
                .map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (val) {
              setState(() {
                _selectedCategory = val;
                _updateAutoWalletLogic();
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSuntikModalForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Target Dana", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _buildRadioOption("Uang Perusahaan (L1)", _companyWalletId)),
            const SizedBox(width: 10),
            Expanded(child: _buildRadioOption("Kas Bendahara (L2)", _treasurerWalletId)),
          ],
        ),
        const SizedBox(height: 20),
        _modernTextField(
          controller: _capitalAmountCtrl,
          label: "Nominal Modal",
          isCurrency: true,
          onChanged: (_) => _calculateTotal(),
        ),
      ],
    );
  }

  Widget _buildItemList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Rincian Item", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54)),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _items.length,
          separatorBuilder: (c, i) => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Divider(color: Colors.grey, thickness: 0.5),
          ),
          itemBuilder: (context, index) => _buildItemRow(index),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton.icon(
            onPressed: _addItem,
            style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                backgroundColor: AppColors.primary.withOpacity(0.05),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
            ),
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: const Text("Tambah Item Lain"),
          ),
        ),
      ],
    );
  }

  Widget _buildItemRow(int index) {
    final item = _items[index];
    return Column(
      key: item.key,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: _modernTextField(
                controller: item.name,
                label: "Nama Barang / Jasa",
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: _modernTextField(
                controller: item.unit,
                label: "Satuan",
                hint: "Pcs",
              ),
            ),
            if (_items.length > 1)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: IconButton(onPressed: () => _removeItem(index), icon: const Icon(Icons.remove_circle, color: Colors.redAccent, size: 22)),
              )
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 4,
              child: _modernTextField(
                controller: item.price,
                label: "Harga Satuan",
                isCurrency: true,
                onChanged: (_) => _calculateTotal(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: _modernTextField(
                controller: item.qty,
                label: "QTY",
                isNumber: true,
                isCenter: true,
                onChanged: (_) => _calculateTotal(),
              ),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildBottomActionBar(bool isPending) {
    Color btnColor;
    String btnText;

    if (isPending) {
      btnColor = Colors.orange[800]!;
      btnText = "AJUKAN APPROVAL";
    } else {
      btnColor = _isIncome ? AppColors.success : AppColors.error;
      btnText = "SIMPAN TRANSAKSI";
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -4))]),
      child: SafeArea(
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Total Estimasi", style: TextStyle(color: Colors.grey, fontSize: 12)),
                Text(
                    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(_totalEstimated),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: btnColor)
                ),
              ],
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: _isLoading ? null : _submitTransaction,
              style: ElevatedButton.styleFrom(
                backgroundColor: btnColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(btnText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            )
          ],
        ),
      ),
    );
  }

  // --- CUSTOM WIDGETS ---

  Widget _modernTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool isCurrency = false,
    bool isNumber = false,
    bool isCenter = false,
    Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: (isCurrency || isNumber) ? TextInputType.number : TextInputType.text,
      inputFormatters: isCurrency ? [CurrencyInputFormatter()] : [],
      textAlign: isCenter ? TextAlign.center : TextAlign.start,
      onChanged: onChanged,
      validator: (v) => v!.isEmpty ? "Wajib" : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: isCurrency ? "Rp " : null,
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black12, width: 1.5)),
        labelStyle: const TextStyle(color: Colors.black45, fontSize: 13),
      ),
    );
  }

  Widget _modernDropdown({
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black54),
              style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500, fontSize: 14),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRadioOption(String label, String walletId) {
    bool selected = _selectedWalletId == walletId;
    return GestureDetector(
      onTap: () => setState(() => _selectedWalletId = walletId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
            border: Border.all(color: selected ? AppColors.primary : Colors.grey.shade200, width: selected ? 1.5 : 1),
            borderRadius: BorderRadius.circular(12),
            color: selected ? AppColors.primary.withOpacity(0.05) : Colors.white
        ),
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.bold : FontWeight.normal, color: selected ? AppColors.primary : Colors.black54)),
      ),
    );
  }

  void _addItem() => setState(() => _items.add(_ItemController()));
  void _removeItem(int index) { if (_items.length > 1) setState(() { _items[index].dispose(); _items.removeAt(index); _calculateTotal(); }); }
}