import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../data/debt_repository.dart';
import '../../debts/domain/debt_model.dart';

class AddDebtScreen extends StatefulWidget {
  final DebtModel? debtToEdit; // Jika null = Mode Tambah, Jika isi = Mode Edit

  const AddDebtScreen({super.key, this.debtToEdit});

  @override
  State<AddDebtScreen> createState() => _AddDebtScreenState();
}

class _AddDebtScreenState extends State<AddDebtScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _amountController;
  late TextEditingController _noteController;
  late TextEditingController _bankController;
  late TextEditingController _rekController;

  late DateTime _loanDate;
  late DateTime _dueDate;
  String _selectedBranch = 'bst_box';
  bool _isLoading = false;

  final List<Map<String, String>> _branches = [
    {'id': 'bst_box', 'name': 'Box Factory'},
    {'id': 'm_alfa', 'name': 'Maint. Alfa'},
    {'id': 'saufa', 'name': 'Saufa Olshop'},
  ];

  @override
  void initState() {
    super.initState();
    // Inisialisasi Data (Jika Edit Mode)
    final d = widget.debtToEdit;
    _nameController = TextEditingController(text: d?.name);
    _amountController = TextEditingController(text: d != null ? d.amount.toStringAsFixed(0) : '');
    _noteController = TextEditingController(text: d?.note);
    _bankController = TextEditingController(text: d?.bankName);
    _rekController = TextEditingController(text: d?.accountNumber);

    _loanDate = d?.loanDate ?? DateTime.now();
    _dueDate = d?.dueDate ?? DateTime.now().add(const Duration(days: 30)); // Default 30 hari
    _selectedBranch = d?.branchId ?? 'bst_box';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    _bankController.dispose();
    _rekController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isLoanDate) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isLoanDate ? _loanDate : _dueDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        if (isLoanDate) _loanDate = picked; else _dueDate = picked;
      });
    }
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final double amount = double.parse(_amountController.text.replaceAll('.', ''));

      // Buat Object Model
      final newDebt = DebtModel(
        id: widget.debtToEdit?.id ?? '', // ID kosong jika tambah baru
        name: _nameController.text,
        amount: amount,
        branchId: _selectedBranch,
        note: _noteController.text,
        status: widget.debtToEdit?.status ?? 'unpaid',
        type: 'payable',
        source: widget.debtToEdit?.source ?? 'manual',
        createdAt: widget.debtToEdit?.createdAt ?? DateTime.now(),
        // Field Baru
        loanDate: _loanDate,
        dueDate: _dueDate,
        bankName: _bankController.text,
        accountNumber: _rekController.text,
      );

      if (widget.debtToEdit == null) {
        // Mode Tambah: Kirim 1 Object newDebt (sesuai Repository yang baru)
        await DebtRepository().addDebt(newDebt);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Utang Berhasil Disimpan")));
      } else {
        // Mode Edit
        await DebtRepository().updateDebt(newDebt);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Data Utang Diperbarui")));
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isEdit = widget.debtToEdit != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? "Edit Utang" : "Catat Utang Baru"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Bagian 1: Info Dasar
              const Text("Informasi Peminjam", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: "Nama Pemberi Utang (Kreditur)", border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? "Wajib diisi" : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                inputFormatters: [CurrencyInputFormatter()],
                decoration: const InputDecoration(labelText: "Nominal (Rp)", prefixText: "Rp ", border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? "Wajib diisi" : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField(
                value: _selectedBranch,
                items: _branches.map((b) => DropdownMenuItem(value: b['id'], child: Text(b['name']!))).toList(),
                onChanged: (val) => setState(() => _selectedBranch = val as String),
                decoration: const InputDecoration(labelText: "Beban Cabang", border: OutlineInputBorder()),
              ),

              const SizedBox(height: 24),
              // Bagian 2: Tanggal & Bank
              const Text("Detail & Jadwal", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDate(true),
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: "Tgl Pinjam", border: OutlineInputBorder()),
                        child: Text(DateFormat('dd/MM/yyyy').format(_loanDate)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDate(false),
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: "Jatuh Tempo", border: OutlineInputBorder()),
                        child: Text(DateFormat('dd/MM/yyyy').format(_dueDate), style: const TextStyle(color: Colors.red)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _bankController,
                      decoration: const InputDecoration(labelText: "Bank", border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _rekController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "No. Rekening", border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: "Catatan Tambahan", border: OutlineInputBorder()),
              ),

              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(isEdit ? "SIMPAN PERUBAHAN" : "SIMPAN UTANG"),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}