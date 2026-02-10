import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';

import '../../../models/transaction_model.dart';
import '../../approval/data/request_repository.dart';
import '../../approval/domain/request_model.dart';
import '../data/transaction_repository.dart';

class AddTransactionScreen extends StatefulWidget {
  final String? branchId;
  final TransactionModel? transactionToEdit; // Parameter untuk Mode Edit

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
  void dispose() { name.dispose(); unit.dispose(); qty.dispose(); price.dispose(); }
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final TransactionRepository _repo = TransactionRepository();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- CONFIG ---
  final String _companyWalletId = 'company_wallet';
  final String _treasurerWalletId = 'treasurer_wallet';

  String _userRole = 'admin_branch';
  String _userBranchId = '';
  String _userName = '';
  bool _isLoading = false;

  // --- STATE UI ---
  bool _isIncome = false;
  String? _selectedBranchId;
  String? _selectedWalletId;
  DateTime _selectedDate = DateTime.now();

  String? _selectedCategory;
  final TextEditingController _customCategoryCtrl = TextEditingController();
  final TextEditingController _capitalAmountCtrl = TextEditingController();

  final List<String> _incomeCategories = ['Penjualan', 'Jasa', 'Lainnya'];
  final List<String> _expenseCategories = ['Harian', 'Belanja Perusahaan', 'Beban Perusahaan', 'Maintenance', 'Gaji', 'Lainnya'];

  List<_ItemController> _items = [];
  double _totalEstimated = 0;

  @override
  void initState() {
    super.initState();
    _initUserAndData();

    // LOAD DATA JIKA EDIT MODE
    if (widget.transactionToEdit != null) {
      _loadEditData();
    } else {
      _addItem(); // Default 1 item kosong
    }
  }

  void _loadEditData() {
    final tx = widget.transactionToEdit!;
    _isIncome = tx.type == 'income';
    _selectedCategory = tx.category;
    // Cek apakah kategori ada di list default, jika tidak masuk ke "Lainnya" atau custom
    if (!_incomeCategories.contains(tx.category) && !_expenseCategories.contains(tx.category)) {
      // Logic sederhana: jika kategori custom, bisa dimasukkan ke logic lain
      // Disini kita asumsi kategori sesuai list atau masuk Lainnya
    }

    _selectedWalletId = tx.walletId;
    _selectedBranchId = tx.relatedBranchId;
    _selectedDate = tx.date;
    _totalEstimated = tx.amount;

    // Parsing Item (Simplifikasi: Gabung jadi 1 item edit)
    final item = _ItemController();
    item.name.text = tx.description;
    item.price.text = NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(tx.amount);
    item.qty.text = '1';
    _items.add(item);
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

          // Jika Mode Tambah Baru, Set Default
          if (widget.transactionToEdit == null) {
            if (_userRole == 'owner') {
              _selectedBranchId = widget.branchId ?? 'bst_box';
            } else {
              _selectedBranchId = _userBranchId;
            }
            _selectedCategory = _isIncome ? _incomeCategories.first : 'Harian';
            _updateAutoWalletLogic();
          }
        });
      }
    }
  }

  void _updateAutoWalletLogic() {
    // Jangan ubah wallet otomatis jika sedang Edit (kecuali user ganti kategori/cabang sengaja)
    // Tapi untuk keamanan data lama, kita biarkan user manual atau logic ini berjalan jika kategori berubah.
    // Disini kita jalankan logic standard.

    if (_selectedBranchId == null && _selectedCategory != 'Suntikan Modal') return;

    setState(() {
      if (_isIncome) {
        if (_selectedCategory == 'Suntikan Modal' && _userRole == 'owner') {
          _selectedWalletId = _treasurerWalletId;
        } else {
          _selectedWalletId = _companyWalletId;
        }
      } else {
        if (_selectedCategory == 'Harian') {
          _selectedWalletId = _getBranchWalletId(_selectedBranchId!);
        } else {
          _selectedWalletId = _treasurerWalletId;
        }
      }
    });
  }

  String _getBranchWalletId(String branchId) {
    switch (branchId) {
      case 'm_alfa': return 'petty_alfa';
      case 'saufa': return 'petty_saufa';
      case 'bst_box': return 'petty_box';
      default: return 'petty_box';
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

  Future<void> _submitTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    if (_totalEstimated <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Total nominal tidak boleh 0")));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;

      // 1. SIAPKAN DESKRIPSI
      String description = "";
      if (_isIncome && _selectedCategory == 'Suntikan Modal') {
        description = "Suntikan Modal";
      } else {
        description = _items.map((e) {
          String priceFmt = NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(double.tryParse(e.price.text.replaceAll('.', '')) ?? 0);
          return "${e.name.text} (${e.qty.text} ${e.unit.text} @ $priceFmt)";
        }).join(", ");
        if (widget.transactionToEdit == null) description += " (Oleh: $_userName)";
      }

      // 2. KATEGORI FINAL
      String finalCategory = _selectedCategory ?? 'Umum';
      if (finalCategory == 'Lainnya' && _customCategoryCtrl.text.isNotEmpty) {
        finalCategory = _customCategoryCtrl.text;
      }

      // ============================================================
      // [FIX KRITIKAL] LOGIKA DETEKSI APPROVAL YANG LEBIH KETAT
      // ============================================================

      // Cek 1: Apakah Pengeluaran?
      bool isExpense = !_isIncome;

      // Cek 2: Apakah User adalah Admin Cabang (Bukan Owner)?
      bool isAdminBranch = _userRole != 'owner';

      // Cek 3: Apakah Kategori WAJIB Approval? (Semua kecuali 'Harian')
      bool isRestrictedCategory = finalCategory != 'Harian';

      // KEPUTUSAN FINAL:
      bool needsApproval = isAdminBranch && isExpense && isRestrictedCategory;

      // Debugging Print (Cek di Run tab jika masih lolos)
      print("DEBUG APPROVAL -> Role: $_userRole | Kat: $finalCategory | NeedsApproval: $needsApproval");

      // --- JALUR A: WAJIB APPROVAL ---
      if (needsApproval) {
        // Pastikan target wallet diset ke Pusat jika logic UI meleset
        String targetWallet = _selectedWalletId ?? _treasurerWalletId;
        // Jika masih nyangkut di petty cash, paksa ke treasurer
        if (targetWallet.startsWith('petty_')) targetWallet = _treasurerWalletId;

        final newRequest = RequestModel(
          id: '',
          amount: _totalEstimated,
          category: finalCategory,
          description: description,
          targetWalletId: targetWallet,
          requesterId: user?.uid ?? 'unknown',
          requesterName: _userName,
          branchId: _userBranchId,
          branchName: _getBranchName(_userBranchId),
          status: 'pending',
          createdAt: DateTime.now(),
        );

        // Kirim ke Repository (Otomatis kirim notifikasi juga)
        await RequestRepository().createRequest(newRequest);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("✋ Permintaan Dana TERKIRIM ke Pusat (Menunggu Persetujuan)"),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ));
          Navigator.pop(context);
        }
      }

      // --- JALUR B: LANGSUNG EKSEKUSI (Harian / Pemasukan / Owner) ---
      else {
        TransactionModel newTx = TransactionModel(
          id: widget.transactionToEdit?.id ?? '',
          amount: _totalEstimated,
          type: _isIncome ? 'income' : 'expense',
          category: finalCategory,
          description: description,
          walletId: _selectedWalletId!,
          date: _selectedDate,
          userId: user?.uid ?? 'unknown',
          relatedBranchId: _selectedBranchId,
          status: 'success',
          createdAt: widget.transactionToEdit?.createdAt ?? DateTime.now(),
          deletedAt: null,
          relatedId: widget.transactionToEdit?.relatedId,
          relatedType: widget.transactionToEdit?.relatedType,
        );

        if (widget.transactionToEdit == null) {
          await _repo.addTransaction(newTx);
        } else {
          await _repo.updateTransaction(oldTx: widget.transactionToEdit!, newTx: newTx);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(widget.transactionToEdit == null ? "✅ Transaksi Berhasil Disimpan!" : "✅ Perubahan Disimpan!"),
              backgroundColor: Colors.green
          ));
          Navigator.pop(context);
        }
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: ${e.toString()}"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  void _addItem() => setState(() => _items.add(_ItemController()));

  // ==================== UI WIDGETS ====================

  @override
  Widget build(BuildContext context) {
    bool isSuntikModal = _isIncome && _selectedCategory == 'Suntikan Modal';
    String title = widget.transactionToEdit == null ? "Catat Transaksi" : "Edit Transaksi";

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(title, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w700, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.close, color: Colors.black54), onPressed: () => Navigator.pop(context)),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Toggle Income/Expense (Hanya jika tambah baru)
                    if (widget.transactionToEdit == null) _buildModernToggle(),
                    const SizedBox(height: 24),
                    _buildFormCard(isSuntikModal),
                  ],
                ),
              ),
            ),
          ),
          _buildBottomActionBar(),
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
          _selectedCategory = isIncome ? _incomeCategories.first : 'Harian';
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
        child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: selected ? (isIncome ? AppColors.success : AppColors.error) : Colors.grey[600], fontSize: 14)),
      ),
    );
  }

  Widget _buildFormCard(bool isSuntikModal) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5))]),
      child: Column(
        children: [
          // Tanggal
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
              if (picked != null) setState(() => _selectedDate = picked);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [const Icon(Icons.calendar_today, size: 18, color: Colors.blue), const SizedBox(width: 10), Text(DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(_selectedDate), style: const TextStyle(fontWeight: FontWeight.w500))]),
            ),
          ),
          const SizedBox(height: 20),

          // [FIX] DROPDOWNS (DENGAN OVERFLOW PROTECTION)
          _buildDropdowns(isSuntikModal),

          const SizedBox(height: 20),

          // Wallet Info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("Sumber Dana / Tujuan", style: TextStyle(fontSize: 10, color: Colors.grey)),
              const SizedBox(height: 4),
              Row(children: [
                Icon(_isIncome ? Icons.account_balance_wallet : Icons.payment, size: 16, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Text(_getWalletNameDisplay(), style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[800], fontSize: 13)),
              ])
            ]),
          ),
          const SizedBox(height: 20),

          if (isSuntikModal) _buildSuntikModalForm() else _buildItemList(),
        ],
      ),
    );
  }

  // [FIX UTAMA] Dropdown dengan isExpanded & Ellipsis
  Widget _buildDropdowns(bool isSuntikModal) {
    bool showBranchDropdown = _userRole == 'owner' && !isSuntikModal;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showBranchDropdown) ...[
          Expanded(
            flex: 4,
            child: _modernDropdown(
                label: "Cabang",
                value: _selectedBranchId,
                items: const [
                  DropdownMenuItem(value: 'bst_box', child: Text("Box Factory", overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(value: 'm_alfa', child: Text("Maint. Alfa", overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(value: 'saufa', child: Text("Saufa Olshop", overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (val) {
                  setState(() { _selectedBranchId = val; _updateAutoWalletLogic(); });
                }
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          flex: showBranchDropdown ? 6 : 1, // Jika tidak ada cabang, ambil full width
          child: _modernDropdown(
              label: "Kategori",
              value: _selectedCategory,
              items: (_isIncome ? _incomeCategories : _expenseCategories).map((c) =>
                  DropdownMenuItem(
                      value: c,
                      child: Text(c, overflow: TextOverflow.ellipsis) // [FIX] Text overflow
                  )
              ).toList(),
              onChanged: (val) {
                setState(() { _selectedCategory = val; _updateAutoWalletLogic(); });
              }
          ),
        ),
      ],
    );
  }

  // [FIX UTAMA] Helper Dropdown
  Widget _modernDropdown({
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required Function(String?) onChanged
  }) {
    return DropdownButtonFormField<String>(
      isExpanded: true, // [FIX] Agar mematuhi lebar Expanded
      decoration: InputDecoration(
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      value: value,
      items: items,
      onChanged: onChanged,
      selectedItemBuilder: (BuildContext context) {
        return items.map<Widget>((DropdownMenuItem<String> item) {
          return Text(
            item.value ?? '',
            overflow: TextOverflow.ellipsis, // [FIX] Cut text kalau kepanjangan
            maxLines: 1,
          );
        }).toList();
      },
    );
  }

  Widget _buildItemList() {
    return Column(
        children: [
          ListView.separated(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _items.length, separatorBuilder: (c, i) => const Divider(), itemBuilder: (context, index) => _buildItemRow(index)),
          const SizedBox(height: 10),
          if (widget.transactionToEdit == null) // Hide add item saat edit
            TextButton.icon(onPressed: _addItem, icon: const Icon(Icons.add), label: const Text("Tambah Item"))
        ]
    );
  }

  Widget _buildItemRow(int index) {
    final item = _items[index];
    return Column(
      children: [
        TextFormField(controller: item.name, decoration: const InputDecoration(labelText: "Nama Item / Deskripsi")),
        Row(children: [
          Expanded(child: TextFormField(controller: item.price, decoration: const InputDecoration(labelText: "Harga"), keyboardType: TextInputType.number, inputFormatters: [CurrencyInputFormatter()], onChanged: (_) => _calculateTotal())),
          const SizedBox(width: 10),
          Expanded(child: TextFormField(controller: item.qty, decoration: const InputDecoration(labelText: "Qty"), keyboardType: TextInputType.number, onChanged: (_) => _calculateTotal())),
        ])
      ],
    );
  }

  Widget _buildSuntikModalForm() { return TextFormField(controller: _capitalAmountCtrl, keyboardType: TextInputType.number, inputFormatters: [CurrencyInputFormatter()], onChanged: (_) => _calculateTotal(), decoration: const InputDecoration(labelText: "Nominal Modal")); }

  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(_totalEstimated), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _isIncome ? AppColors.success : AppColors.error)),
          ElevatedButton(
            onPressed: _isLoading ? null : _submitTransaction,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
            child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : Text(widget.transactionToEdit == null ? "SIMPAN" : "UPDATE"),
          )
        ],
      ),
    );
  }
}