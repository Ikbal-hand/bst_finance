import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/constants/app_colors.dart';
import '../../debts/presentation/debt_list_screen.dart';

class NotificationScreen extends StatefulWidget {
  final String branchId;
  const NotificationScreen({super.key, required this.branchId});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _markAllAsRead(); // Opsional: Tandai terbaca saat dibuka
  }

  // Menandai semua notifikasi sebagai terbaca saat layar dibuka
  Future<void> _markAllAsRead() async {
    final query = FirebaseFirestore.instance
        .collection('notifications')
        .where('to_branch', whereIn: [widget.branchId, 'all'])
        .where('is_read', isEqualTo: false);

    final snapshot = await query.get();
    final batch = FirebaseFirestore.instance.batch();

    for (var doc in snapshot.docs) {
      batch.update(doc.reference, {'is_read': true});
    }
    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pusat Notifikasi", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: "Pesan Masuk"),
            Tab(text: "Jatuh Tempo (H-3)"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildNotificationList(),
        ],
      ),
    );
  }

  // --- TAB 1: LIST NOTIFIKASI UMUM ---
// --- TAB 1: LIST NOTIFIKASI UMUM ---
  Widget _buildNotificationList() {
    // [FIX KRITIKAL]
    // Jika user login sebagai 'owner' (ID: owner), dia harus baca notifikasi tujuan 'pusat'.
    // Jika user login sebagai admin cabang (ID: bst_box), dia baca notifikasi tujuan 'bst_box'.

    final String targetBranch = widget.branchId == 'owner' ? 'pusat' : widget.branchId;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
      // [FIX] Gunakan targetBranch yang sudah dilogika di atas
          .where('to_branch', whereIn: [targetBranch, 'all'])
          .orderBy('date', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text("Belum ada notifikasi baru"));
        }

        final docs = snapshot.data!.docs;
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (c, i) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;

            // Safe Date Parsing
            DateTime date = DateTime.now();
            if (data['date'] != null) {
              date = (data['date'] as Timestamp).toDate();
            }

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blue.shade50,
                child: const Icon(Icons.notifications, color: Colors.blue, size: 20),
              ),
              title: Text(data['title'] ?? 'Info', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data['message'] ?? '-', maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(DateFormat('dd MMM HH:mm').format(date), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- TAB 2: LIST JATUH TEMPO (FIX ERROR NULL) ---
}