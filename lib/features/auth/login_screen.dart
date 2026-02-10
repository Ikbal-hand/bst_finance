import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// [FIX IMPORT PATH] Sesuaikan dengan struktur folder Anda
import '../dashboard/presentation/dashboard_screen.dart';
import 'logic/auth_cubit.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isObscure = true;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  void _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedEmail = prefs.getString('saved_email');
    if (savedEmail != null) {
      setState(() {
        _emailController.text = savedEmail;
        _rememberMe = true;
      });
    }
  }

  void _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Email dan Password wajib diisi")));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString('saved_email', email);
    } else {
      await prefs.remove('saved_email');
    }

    if (mounted) {
      context.read<AuthCubit>().login(email, password);
    }
    TextInput.finishAutofillContext();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: BlocListener<AuthCubit, AuthState>(
        listener: (context, state) {
          if (state is AuthSuccess) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
          } else if (state is AuthFailure) {
            // [FIX ERROR PROPERTY] Gunakan state.message
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message), backgroundColor: Colors.red));
          }
        },
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: AutofillGroup(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.account_balance_wallet, size: 80, color: Colors.blue),
                  const SizedBox(height: 20),
                  const Text("BST FINANCE", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 40),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(labelText: "Email", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: _isObscure,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: "Password",
                      suffixIcon: IconButton(icon: Icon(_isObscure ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _isObscure = !_isObscure)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onEditingComplete: _login,
                  ),
                  Row(children: [Checkbox(value: _rememberMe, onChanged: (val) => setState(() => _rememberMe = val!)), const Text("Ingat Email Saya")]),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: BlocBuilder<AuthCubit, AuthState>(
                      builder: (context, state) {
                        return ElevatedButton(
                          onPressed: (state is AuthLoading) ? null : _login,
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[800]),
                          child: (state is AuthLoading) ? const CircularProgressIndicator(color: Colors.white) : const Text("MASUK", style: TextStyle(color: Colors.white)),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}