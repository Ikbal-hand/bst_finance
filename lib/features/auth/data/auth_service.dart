import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  // Fungsi Login
  Future<User?> login(String email, String password) async {
    try {
      final UserCredential userCredential = await _firebaseAuth
          .signInWithEmailAndPassword(email: email, password: password);
      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        throw Exception('Email tidak terdaftar.');
      } else if (e.code == 'wrong-password') {
        throw Exception('Password salah.');
      } else {
        throw Exception('Terjadi kesalahan: ${e.message}');
      }
    } catch (e) {
      // INI BAGIAN PENTING: Print error asli ke layar Debug Console
      print("ERROR ASLI: $e");
      throw Exception('Terjadi kesalahan sistem: $e'); // Tampilkan error di layar HP juga
    }
  }

  // Fungsi Logout
  Future<void> logout() async {
    await _firebaseAuth.signOut();
  }
}