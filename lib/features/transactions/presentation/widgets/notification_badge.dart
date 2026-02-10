import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Sesuaikan import ini dengan struktur folder Anda
import '../../../notification/presentation/notification_screen.dart';

class NotificationBadge extends StatelessWidget {
  final String branchId;
  final String userRole;

  const NotificationBadge({
    super.key,
    required this.branchId,
    required this.userRole
  });

  @override
  Widget build(BuildContext context) {
    // [FIX UTAMA DISINI]
    // Jika User adalah Owner, maka dia harus mendengarkan notifikasi untuk 'pusat'.
    // Jika Admin Cabang, dia mendengarkan notifikasi untuk 'bst_box', dll.

    String targetBranch = branchId;
    if (userRole == 'owner' || branchId == 'pusat') {
      targetBranch = 'pusat';
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
      // Filter: Pesan untuk (targetBranch) ATAU untuk ('all')
          .where('to_branch', whereIn: [targetBranch, 'all'])
          .where('is_read', isEqualTo: false) // Hanya yang belum dibaca
          .snapshots(),
      builder: (context, snapshot) {

        int unreadCount = 0;
        if (snapshot.hasData) {
          unreadCount = snapshot.data!.docs.length;
        }

        return Stack(
          children: [
            // A. ICON LONCENG
            IconButton(
              icon: const Icon(Icons.notifications_outlined, color: Colors.black),
              onPressed: () {
                // Saat diklik, buka layar notifikasi
                // Kita kirim parameter branchId asli agar logika di dalam screen tetap jalan
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => NotificationScreen(
                        branchId: userRole == 'owner' ? 'owner' : branchId
                    ),
                  ),
                );
              },
            ),

            // B. DOT MERAH (BADGE)
            if (unreadCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4), // Padding sedikit lebih besar
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18, // Ukuran minimum dot
                    minHeight: 18,
                  ),
                  child: Center(
                    child: Text(
                      unreadCount > 9 ? '9+' : '$unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}