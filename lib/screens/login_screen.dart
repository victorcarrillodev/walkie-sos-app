import 'package:app_walkie/screens/contacts_screen.dart';
import 'package:flutter/material.dart';
import '../core/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  void _iniciarSesion() async {
    // Evitar que envíen datos vacíos
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) return;

    setState(() {
      _isLoading = true; // Mostramos círculo de carga
    });
    
    // Llamamos a nuestro servicio
    bool exito = await AuthService.login(
      _emailController.text.trim(),
      _passwordController.text,
    );

    setState(() {
      _isLoading = false; // Ocultamos círculo de carga
    });

    if (exito) {
      // Si el login fue bien, cambiamos de pantalla y no dejamos que vuelva atrás
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ContactsScreen()),
      );
    } else {
      // Si falló (credenciales incorrectas, servidor apagado, etc.)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al iniciar sesión. Verifica tus datos.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Iniciar Sesión Zello Clone'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Correo electrónico',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Contraseña',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true, // Oculta la contraseña
            ),
            const SizedBox(height: 32),
            _isLoading 
              ? const CircularProgressIndicator()
              : SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _iniciarSesion,
                    child: const Text('Entrar', style: TextStyle(fontSize: 18)),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}