import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'RTpage.dart';
import 'Registrations/signup.dart';
import 'TestsFiles.dart';
import '../models/dataset_record_model.dart';
import '../services/database_service.dart';
import '../widgets/entry_animation.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/loading_widget.dart';

// ignore: must_be_immutable
class ProfileDash extends StatefulWidget {
  const ProfileDash({super.key});

  @override
  State<ProfileDash> createState() => _ProfileDashState();
}

class _ProfileDashState extends State<ProfileDash> {
  String profileImagePath = 'assets/profiledemo.png';
  TextEditingController profileImageController = TextEditingController();

  Map<String, dynamic>? userData;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchUserProfile();
  }

  Future<void> fetchUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        userData = null;
        isLoading = false;
      });
      return;
    }

    final fallbackProfile = _fallbackProfileFor(user);
    var profile = fallbackProfile;

    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final doc = await docRef.get();
      profile = {...fallbackProfile, if (doc.exists) ...?doc.data()};

      if (!doc.exists) {
        await docRef.set({
          ...fallbackProfile,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {
      profile = fallbackProfile;
    }

    if (!mounted) return;
    setState(() {
      userData = profile;
      isLoading = false;
    });
  }

  Map<String, dynamic> _fallbackProfileFor(User user) {
    final email = user.email ?? '';
    final displayName =
        user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : email.split('@').first;

    return {
      'name': displayName,
      'email': email,
      'phone': 'Not provided',
      'bloodGroup': 'Not provided',
      'bio': 'Not provided',
      'address': 'Not provided',
      'role': 'user',
    };
  }

  String _profileValue(String key) {
    final value = userData?[key];
    if (value == null) return '';
    final text = value.toString();
    return text == 'Not provided' ? '' : text;
  }

  Future<void> _openEditProfileDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: _profileValue('name'));
    final phoneController = TextEditingController(text: _profileValue('phone'));
    final bloodGroupController = TextEditingController(
      text: _profileValue('bloodGroup'),
    );
    final bioController = TextEditingController(text: _profileValue('bio'));
    final addressController = TextEditingController(
      text: _profileValue('address'),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Edit Profile'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Name'),
                      validator:
                          (value) =>
                              value == null || value.trim().isEmpty
                                  ? 'Please enter your name'
                                  : null,
                    ),
                    TextFormField(
                      controller: phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    TextFormField(
                      controller: bloodGroupController,
                      decoration: const InputDecoration(
                        labelText: 'Blood Group',
                      ),
                    ),
                    TextFormField(
                      controller: bioController,
                      decoration: const InputDecoration(labelText: 'Bio'),
                      minLines: 2,
                      maxLines: 3,
                    ),
                    TextFormField(
                      controller: addressController,
                      decoration: const InputDecoration(labelText: 'Address'),
                      minLines: 2,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;

                  final profile = {
                    'name': nameController.text.trim(),
                    'email': user.email ?? userData?['email'] ?? '',
                    'phone': phoneController.text.trim(),
                    'bloodGroup': bloodGroupController.text.trim(),
                    'bio': bioController.text.trim(),
                    'address': addressController.text.trim(),
                    'role': userData?['role'] ?? 'user',
                    'updatedAt': FieldValue.serverTimestamp(),
                  };

                  try {
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .set(profile, SetOptions(merge: true));

                    try {
                      await user.updateDisplayName(profile['name']);
                    } catch (_) {
                      // Firestore profile is the source of truth for this page.
                    }

                    if (!mounted) return;
                    setState(() {
                      userData = {
                        ...?userData,
                        ...profile,
                        'phone':
                            profile['phone']!.isEmpty
                                ? 'Not provided'
                                : profile['phone'],
                        'bloodGroup':
                            profile['bloodGroup']!.isEmpty
                                ? 'Not provided'
                                : profile['bloodGroup'],
                        'bio':
                            profile['bio']!.isEmpty
                                ? 'Not provided'
                                : profile['bio'],
                        'address':
                            profile['address']!.isEmpty
                                ? 'Not provided'
                                : profile['address'],
                      };
                    });
                    Navigator.pop(dialogContext, true);
                  } catch (_) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not update profile.'),
                      ),
                    );
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
    );

    nameController.dispose();
    phoneController.dispose();
    bloodGroupController.dispose();
    bioController.dispose();
    addressController.dispose();

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully.')),
      );
    }
  }

  @override
  void dispose() {
    profileImageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Profile'),
        centerTitle: true,
        backgroundColor: const Color.fromARGB(255, 82, 156, 199),
      ),
      endDrawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(40),
                child: Image.asset(
                  'assets/profiledemo.png',
                  width: 80,
                  height: 80,
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.home),
              title: Text('Home'),
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => Testsfiles()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.settings),
              title: Text('Settings'),
              onTap: () {
                // Handle the settings tap here
              },
            ),
            ListTile(
              leading: Icon(Icons.add_chart_rounded),
              title: Text('Submitted Results'),
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const RTpage()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.settings),
              title: Text('About Us'),
              onTap: () {
                // Handle the settings tap here
              },
            ),
            ListTile(
              leading: Icon(Icons.logout),
              title: Text('Logout'),
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => SignUpPage()),
                );
              },
            ),
          ],
        ),
      ),
      //profile details container//
      body:
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : userData == null
              ? const Center(child: Text('No profile data found.'))
              : Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      image: DecorationImage(
                        image: AssetImage('assets/bg.jpg'),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 88),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          EntryAnimation(
                            child: Container(
                              width: double.infinity,
                              margin: EdgeInsets.all(12),
                              padding: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                shape: BoxShape.rectangle,
                                color: Color(0xFF89A8B2),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.5),
                                    spreadRadius: 2,
                                    blurRadius: 5,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(0),
                                    child: Image.asset(
                                      'assets/profiledemo.png',
                                      width: 150,
                                      height: 150,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  SizedBox(height: 7),
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: 'Name: ',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black,
                                          ),
                                        ),
                                        TextSpan(
                                          text: userData?['name'] ?? '',
                                          style: TextStyle(
                                            fontSize: 15,
                                            color: Colors.black38,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(height: 7),
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: 'Email: ',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black,
                                          ),
                                        ),
                                        TextSpan(
                                          text: userData?['email'] ?? '',
                                          style: TextStyle(
                                            fontSize: 15,
                                            color: Colors.black38,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(height: 7),
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: 'Phone Number: ',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black,
                                          ),
                                        ),
                                        TextSpan(
                                          text: userData?['phone'] ?? '',
                                          style: TextStyle(
                                            fontSize: 15,
                                            color: Colors.black38,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(height: 7),
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: 'Blood Group:  ',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black,
                                          ),
                                        ),
                                        TextSpan(
                                          text: userData?['bloodGroup'] ?? '',
                                          style: TextStyle(
                                            fontSize: 15,
                                            color: Colors.black38,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(height: 7),
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: 'Bio: ',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black,
                                          ),
                                        ),
                                        TextSpan(
                                          text: userData?['bio'] ?? '',
                                          style: TextStyle(
                                            fontSize: 15,
                                            color: Colors.black38,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(height: 7),
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: 'Address: ',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black,
                                          ),
                                        ),
                                        TextSpan(
                                          text: userData?['address'] ?? '',
                                          style: TextStyle(
                                            fontSize: 15,
                                            color: Colors.black38,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(height: 7),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      ElevatedButton(
                                        onPressed: _openEditProfileDialog,
                                        child: Icon(Icons.edit),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: 10),
                          const EntryAnimation(index: 1, child: TakeAtest()),
                          SizedBox(height: 10),
                          const EntryAnimation(index: 2, child: TestHistory()),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
    );
  }
}

class TakeAtest extends StatelessWidget {
  const TakeAtest({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Color(0xffE5E1DA),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'If you have not taken any tests yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => Testsfiles()),
                );
              },
              child: Text('Take a Test'),
            ),
          ],
        ),
      ),
    );
  }
}

class TestHistory extends StatelessWidget {
  const TestHistory({super.key});

  @override
  Widget build(BuildContext context) {
    final service = DatabaseService();

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const RTpage()),
        );
      },
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          minHeight: 280,
          maxHeight: MediaQuery.of(context).size.height * 0.55,
        ),
        decoration: BoxDecoration(
          color: Color(0xffB3C8CF),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: 10),
              Text(
                'Submitted Results',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 10),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: service.watchCurrentUserRecords(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const LoadingWidget();
                    }
                    if (snapshot.hasError) {
                      return EmptyStateWidget(
                        message:
                            'Could not load submissions: ${snapshot.error}',
                      );
                    }

                    final records =
                        (snapshot.data?.docs ?? [])
                            .map(DatasetRecordModel.fromFirestore)
                            .toList()
                          ..sort(_newestFirst);
                    if (records.isEmpty) {
                      return const EmptyStateWidget(
                        message: 'No submissions yet.',
                      );
                    }

                    return ListView.builder(
                      itemCount: records.length,
                      itemBuilder: (context, index) {
                        final record = records[index];
                        return EntryAnimation(
                          index: index,
                          child: Card(
                            margin: EdgeInsets.symmetric(
                              vertical: 5,
                              horizontal: 11,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    record.kitDisplayName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      Chip(label: Text(record.reviewStatus)),
                                      Chip(label: Text(record.selectedResult)),
                                    ],
                                  ),
                                  Text('Result: ${record.selectedResult}'),
                                  Text(
                                    'Submitted: ${record.submittedAtDigital}',
                                  ),
                                  Text(
                                    'Kit ID: ${record.kitId.isEmpty ? 'Not provided' : record.kitId}',
                                  ),
                                  Text('Kit Name: ${record.kitDisplayName}'),
                                  if (record.imageUrl.isNotEmpty ||
                                      record.imageName.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    _SubmissionPhotoPreview(record: record),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubmissionPhotoPreview extends StatelessWidget {
  const _SubmissionPhotoPreview({required this.record});

  final DatasetRecordModel record;

  @override
  Widget build(BuildContext context) {
    if (record.imageUrl.isEmpty) {
      return const Row(
        children: [
          Icon(Icons.image_outlined, size: 18),
          SizedBox(width: 6),
          Text('Photo attached'),
        ],
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        record.imageUrl,
        width: double.infinity,
        height: 96,
        fit: BoxFit.cover,
        errorBuilder:
            (_, __, ___) => const Row(
              children: [
                Icon(Icons.broken_image_outlined, size: 18),
                SizedBox(width: 6),
                Text('Photo attached'),
              ],
            ),
      ),
    );
  }
}

int _newestFirst(DatasetRecordModel a, DatasetRecordModel b) {
  final aDate =
      a.createdAt ?? a.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final bDate =
      b.createdAt ?? b.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  return bDate.compareTo(aDate);
}
