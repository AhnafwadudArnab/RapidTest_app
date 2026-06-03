import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:myproject/All%20in%20one/Registrations/forgetpass.dart';
import 'package:myproject/All%20in%20one/Registrations/login.dart';
import 'package:myproject/All%20in%20one/Registrations/signup.dart';
import 'package:myproject/All%20in%20one/TestsFiles.dart' show Testsfiles;
import 'package:myproject/All%20in%20one/ADMIN/adminLogin.dart';
import 'package:myproject/OnBoard/frontpage.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Rapid Test',
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthGate(),
        '/Login': (context) => const Login(),
        '/SignUp': (context) => const SignUpPage(),
        '/ForgotPassword': (context) => const ForgetPassword(),
        '/AdminLogin': (context) => const AdminLogin(),
      },
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute(builder: (context) => const AuthGate());
          case '/Login':
            return MaterialPageRoute(builder: (context) => const Login());
          case '/SignUp':
            return MaterialPageRoute(builder: (context) => const SignUpPage());
          case '/ForgotPassword':
            return MaterialPageRoute(
              builder: (context) => const ForgetPassword(),
            );
          case '/AdminLogin':
            return MaterialPageRoute(builder: (context) => const AdminLogin());
          default:
            return MaterialPageRoute(builder: (context) => const AuthGate());
        }
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          return const Testsfiles();
        }

        return const Onboard();
      },
    );
  }
}
