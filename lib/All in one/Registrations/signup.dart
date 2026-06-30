import 'package:email_validator/email_validator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:myproject/All%20in%20one/Firebase/firebase_auth.dart';
import 'package:myproject/widgets/entry_animation.dart';
import 'login.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _SignUpState createState() => _SignUpState();
}

class _SignUpState extends State<SignUpPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.lightBlueAccent,
        //title: Image.asset("assets/hero-overlay_mosque.png", height: 50),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Background image
          Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage("assets/bg.jpg"),
                fit: BoxFit.cover,
              ),
            ),
          ),

          Container(
            margin: const EdgeInsets.only(top: 22.0, left: 20.0, right: 20.0),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.18),
                  EntryAnimation(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      constraints: BoxConstraints(
                        minHeight: MediaQuery.of(context).size.height * 0.62,
                      ),
                      width: MediaQuery.of(context).size.width,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.black.withOpacity(0.2),
                        ),
                        boxShadow: [
                          BoxShadow(
                            spreadRadius: 2.0,
                            blurRadius: 10.0,
                            color: Colors.black.withOpacity(0.1),
                          ),
                        ],
                      ),
                      child: const LoginFormWidget(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LoginFormWidget extends StatefulWidget {
  const LoginFormWidget({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _LoginFormWidgetState createState() => _LoginFormWidgetState();
}

class _LoginFormWidgetState extends State<LoginFormWidget> {
  final _formKey = GlobalKey<FormState>();
  TextEditingController nameController = TextEditingController();
  TextEditingController emailController = TextEditingController();
  TextEditingController confirmPasswordController = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  // final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  bool isPasswordVisible = true;
  bool isLoading = false;
  String? responseMessage;
  final MyFirebaseAuth _auth = MyFirebaseAuth();

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    confirmPasswordController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12.0),
            const Text(
              "Sign Up",
              style: TextStyle(fontSize: 24.0, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12.0),
            // Name field
            TextFormField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                labelStyle: TextStyle(color: Colors.black),
                prefixIcon: Icon(Icons.person, color: Colors.black),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your name';
                }
                return null;
              },
            ),
            const SizedBox(height: 12.0),
            // Email field
            TextFormField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                labelStyle: TextStyle(color: Colors.black),
                prefixIcon: Icon(Icons.email, color: Colors.black),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your email';
                } else if (!EmailValidator.validate(value)) {
                  return 'Please enter a valid email';
                }
                return null;
              },
            ),
            const SizedBox(height: 12.0),
            // Password field
            TextFormField(
              controller: passwordController,
              obscureText: isPasswordVisible,
              decoration: InputDecoration(
                labelText: 'Password',
                labelStyle: const TextStyle(color: Colors.black),
                prefixIcon: const Icon(Icons.lock, color: Colors.black),
                suffixIcon: IconButton(
                  icon: Icon(
                    isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                    color: Colors.black,
                  ),
                  onPressed: () {
                    setState(() {
                      isPasswordVisible = !isPasswordVisible;
                    });
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your password';
                }
                if (value.length < 6) {
                  return 'Password must be at least 6 characters long';
                }
                return null;
              },
            ),
            const SizedBox(height: 12.0),
            // Confirm Password field
            TextFormField(
              controller: confirmPasswordController,
              obscureText: isPasswordVisible,
              decoration: InputDecoration(
                labelText: 'Retype Password',
                labelStyle: const TextStyle(color: Colors.black),
                prefixIcon: const Icon(Icons.lock, color: Colors.black),
                suffixIcon: IconButton(
                  icon: Icon(
                    isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                    color: Colors.black,
                  ),
                  onPressed: () {
                    setState(() {
                      isPasswordVisible = !isPasswordVisible;
                    });
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please confirm your password';
                }
                if (value != passwordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
            const SizedBox(height: 18.0),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 96, 180, 219),
              ),
              onPressed:
                  isLoading
                      ? null
                      : () async {
                        if (_formKey.currentState!.validate()) {
                          setState(() {
                            isLoading = true;
                          });

                          try {
                            final username = nameController.text.trim();
                            final normalizedUsername = _normalizeUsername(
                              username,
                            );
                            final usernameDoc =
                                await FirebaseFirestore.instance
                                    .collection('usernames')
                                    .doc(normalizedUsername)
                                    .get();
                            if (usernameDoc.exists) {
                              Fluttertoast.showToast(
                                msg:
                                    "Username is already taken. Please choose another.",
                              );
                              return;
                            }

                            User? user = await _auth.signUpWithEmailAndPassword(
                              emailController.text,
                              passwordController.text,
                            );

                            if (user != null) {
                              final email = emailController.text.trim();
                              final batch = FirebaseFirestore.instance.batch();
                              batch.set(
                                FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(user.uid),
                                {
                                  'name': username,
                                  'usernameLower': normalizedUsername,
                                  'email': email,
                                  'role': 'user',
                                  'createdAt': FieldValue.serverTimestamp(),
                                  'updatedAt': FieldValue.serverTimestamp(),
                                },
                                SetOptions(merge: true),
                              );
                              batch.set(
                                FirebaseFirestore.instance
                                    .collection('usernames')
                                    .doc(normalizedUsername),
                                {
                                  'uid': user.uid,
                                  'email': email,
                                  'createdAt': FieldValue.serverTimestamp(),
                                  'updatedAt': FieldValue.serverTimestamp(),
                                },
                              );
                              await batch.commit();
                              Fluttertoast.showToast(
                                msg: "Registration successful!",
                              );
                              Get.offAll(() => const Login());
                            } else {
                              Fluttertoast.showToast(
                                msg: "Registration failed. Please try again.",
                              );
                            }
                          } on FirebaseAuthException catch (e) {
                            String errorMessage = "Registration failed";
                            switch (e.code) {
                              case 'email-already-in-use':
                                errorMessage =
                                    "Email is already registered. Please use a different email.";
                                break;
                              case 'invalid-email':
                                errorMessage = "Invalid email format.";
                                break;
                              case 'weak-password':
                                errorMessage =
                                    "Password is too weak. Please use a stronger password.";
                                break;
                              case 'operation-not-allowed':
                                errorMessage =
                                    "Email/password accounts are not enabled.";
                                break;
                              default:
                                errorMessage =
                                    "Registration failed: ${e.message}";
                            }
                            Fluttertoast.showToast(msg: errorMessage);
                          } catch (e) {
                            Fluttertoast.showToast(
                              msg:
                                  "An unexpected error occurred. Please try again.",
                            );
                          } finally {
                            setState(() {
                              isLoading = false;
                            });
                          }
                        }
                      },
              child:
                  isLoading
                      ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                      : const Text(
                        'Register',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
            ),
            TextButton(
              onPressed: () {
                Get.to(() => const Login());
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Already have an account? ",
                    style: TextStyle(color: Colors.black),
                  ),
                  SizedBox(width: 4),
                  Text(
                    "Login",
                    style: TextStyle(
                      fontSize: 20.0,
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _normalizeUsername(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  }
}
