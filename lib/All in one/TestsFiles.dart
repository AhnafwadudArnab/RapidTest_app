import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:myproject/OnBoard/frontpage.dart';

import '../models/dataset_record_model.dart';
import '../services/database_service.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/loading_widget.dart';
import 'qr_result_submission_page.dart';

class Testsfiles extends StatefulWidget {
  const Testsfiles({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<Testsfiles> createState() => _TestsfilesState();
}

class _TestsfilesState extends State<Testsfiles>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseService _databaseService = DatabaseService();
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  late int _selectedIndex;

  static const _pages = [
    _UserPage('Home', 'Rapid Test', Icons.home_rounded),
    _UserPage('Submissions', 'My Submissions', Icons.history_rounded),
    _UserPage('Profile', 'Profile', Icons.person_outline_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex.clamp(0, _pages.length - 1);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _signOut() async {
    try {
      await _auth.signOut();
      Get.offAll(() => const Onboard());
    } catch (e) {
      if (kDebugMode) {
        print('Error: $e');
      }
    }
  }

  void _selectPage(int index) {
    setState(() => _selectedIndex = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    });
  }

  void _openSubmissionPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QrResultSubmissionPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _UserColors.page,
      bottomNavigationBar: _UserBottomNav(
        pages: _pages,
        selectedIndex: _selectedIndex,
        onSelected: _selectPage,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _UserTopBar(page: _pages[_selectedIndex]),
            Expanded(
              child: _AnimatedUserBackground(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontalPadding =
                        constraints.maxWidth <= 420
                            ? 10.0
                            : constraints.maxWidth < 520
                            ? 14.0
                            : 24.0;
                    return ListView(
                      controller: _scrollController,
                      key: ValueKey(_selectedIndex),
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        constraints.maxWidth <= 520 ? 14 : 22,
                        horizontalPadding,
                        34,
                      ),
                      children: [
                        switch (_selectedIndex) {
                          0 => _UserHomePage(
                            pulseAnimation: _pulseAnimation,
                            onUpload: _openSubmissionPage,
                            onHistory: () => _selectPage(1),
                          ),
                          1 => _UserSubmissionsPage(
                            databaseService: _databaseService,
                          ),
                          _ => _UserProfilePage(onLogout: _signOut),
                        },
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserHomePage extends StatelessWidget {
  const _UserHomePage({
    required this.pulseAnimation,
    required this.onUpload,
    required this.onHistory,
  });

  final Animation<double> pulseAnimation;
  final VoidCallback onUpload;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _UserHeroCard(
          pulseAnimation: pulseAnimation,
          onUpload: onUpload,
          onHistory: onHistory,
        ),
        const SizedBox(height: 18),
        _UserActionGrid(onUpload: onUpload, onHistory: onHistory),
        const SizedBox(height: 18),
        _UserPanel(
          title: 'How It Works',
          child: Column(
            children: const [
              _StepRow(
                icon: Icons.add_a_photo_outlined,
                title: 'Upload kit photo',
                subtitle: 'Take a photo or choose one from your device.',
              ),
              SizedBox(height: 12),
              _StepRow(
                icon: Icons.qr_code_scanner_rounded,
                title: 'Read QR details',
                subtitle: 'If the kit has a QR code, scan it for kit info.',
              ),
              SizedBox(height: 12),
              _StepRow(
                icon: Icons.check_circle_outline_rounded,
                title: 'Submit result',
                subtitle: 'Select Positive or Negative and save your report.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UserHeroCard extends StatelessWidget {
  const _UserHeroCard({
    required this.pulseAnimation,
    required this.onUpload,
    required this.onHistory,
  });

  final Animation<double> pulseAnimation;
  final VoidCallback onUpload;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A2F66), Color(0xFF1590C7)],
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: _UserColors.blue.withOpacity(0.22),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          ScaleTransition(
            scale: pulseAnimation,
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.14),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.62),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.qr_code_scanner_rounded,
                size: 56,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Upload Rapid Test Report',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Capture or upload the test photo, then choose the result manually.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFE8F7FF), fontSize: 16),
          ),
          const SizedBox(height: 24),
          _UserPrimaryButton(
            onPressed: onUpload,
            icon: Icons.add_photo_alternate_outlined,
            label: 'Upload Photo',
          ),
          const SizedBox(height: 10),
          _UserGhostButton(
            onPressed: onHistory,
            icon: Icons.history_rounded,
            label: 'My Submissions',
          ),
        ],
      ),
    );
  }
}

class _UserActionGrid extends StatelessWidget {
  const _UserActionGrid({required this.onUpload, required this.onHistory});

  final VoidCallback onUpload;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth =
            constraints.maxWidth >= 700
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: cardWidth,
              child: _ActionCard(
                title: 'Take A Test',
                subtitle: 'Upload a new rapid test result.',
                icon: Icons.science_outlined,
                color: _UserColors.green,
                onTap: onUpload,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _ActionCard(
                title: 'Submitted Results',
                subtitle: 'Review your previous reports.',
                icon: Icons.assignment_turned_in_outlined,
                color: _UserColors.blue,
                onTap: onHistory,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _UserSubmissionsPage extends StatefulWidget {
  const _UserSubmissionsPage({required this.databaseService});

  final DatabaseService databaseService;

  @override
  State<_UserSubmissionsPage> createState() => _UserSubmissionsPageState();
}

class _UserSubmissionsPageState extends State<_UserSubmissionsPage> {
  static const int _pageSize = 20;
  int _pageIndex = 0;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.databaseService.watchCurrentUserRecords(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 80),
            child: LoadingWidget(),
          );
        }
        if (snapshot.hasError) {
          return EmptyStateWidget(
            message: 'Could not load submissions: ${snapshot.error}',
          );
        }

        final records =
            (snapshot.data?.docs ?? [])
                .map(DatasetRecordModel.fromFirestore)
                .toList()
              ..sort(_newestFirst);
        if (records.isEmpty) {
          return const EmptyStateWidget(message: 'No submissions yet.');
        }
        final totalPages = (records.length / _pageSize).ceil();
        final safePageIndex = _pageIndex.clamp(0, totalPages - 1);
        if (safePageIndex != _pageIndex) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _pageIndex = safePageIndex);
          });
        }
        final visibleRecords =
            records.skip(safePageIndex * _pageSize).take(_pageSize).toList();
        final firstRecord = safePageIndex * _pageSize + 1;
        final lastRecord = firstRecord + visibleRecords.length - 1;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(
              title: 'Submitted Results',
              subtitle:
                  'Showing $firstRecord-$lastRecord of ${records.length} report(s).',
            ),
            const SizedBox(height: 16),
            for (final entry in visibleRecords.indexed) ...[
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Duration(
                  milliseconds: 260 + (entry.$1 * 45).clamp(0, 320),
                ),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 18 * (1 - value)),
                      child: child,
                    ),
                  );
                },
                child: _SubmissionCard(record: entry.$2),
              ),
              const SizedBox(height: 12),
            ],
            _PaginationControls(
              pageIndex: safePageIndex,
              totalPages: totalPages,
              onPrevious:
                  safePageIndex == 0
                      ? null
                      : () => setState(() => _pageIndex -= 1),
              onNext:
                  safePageIndex >= totalPages - 1
                      ? null
                      : () => setState(() => _pageIndex += 1),
            ),
          ],
        );
      },
    );
  }
}

class _PaginationControls extends StatelessWidget {
  const _PaginationControls({
    required this.pageIndex,
    required this.totalPages,
    required this.onPrevious,
    required this.onNext,
  });

  final int pageIndex;
  final int totalPages;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: _UserPanel(
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left_rounded),
                label: const Text('Previous'),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${pageIndex + 1} / $totalPages',
              style: const TextStyle(
                color: _UserColors.navy,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right_rounded),
                label: const Text('Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserProfilePage extends StatefulWidget {
  const _UserProfilePage({required this.onLogout});

  final VoidCallback onLogout;

  @override
  State<_UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<_UserProfilePage> {
  final ImagePicker _imagePicker = ImagePicker();
  Map<String, dynamic>? _userData;
  Uint8List? _profilePhotoPreviewBytes;
  bool _isLoading = true;
  bool _isUploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
  }

  Future<void> _fetchUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _userData = null;
        _isLoading = false;
      });
      return;
    }

    final fallback = _fallbackProfileFor(user);
    var profile = fallback;
    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final doc = await docRef.get();
      profile = {...fallback, if (doc.exists) ...?doc.data()};
      if (!doc.exists) {
        await docRef.set({
          ...fallback,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {
      profile = fallback;
    }

    if (!mounted) return;
    setState(() {
      _userData = profile;
      _isLoading = false;
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
      'bio': 'Patient',
      'address': 'Not provided',
      'profilePhotoUrl': '',
      'profilePhotoStoragePath': '',
      'role': 'user',
    };
  }

  String _profileValue(String key) {
    final value = _userData?[key];
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
              FilledButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;

                  final profile = {
                    'name': nameController.text.trim(),
                    'email': user.email ?? _userData?['email'] ?? '',
                    'phone': phoneController.text.trim(),
                    'bloodGroup': bloodGroupController.text.trim(),
                    'bio': 'Patient',
                    'address': addressController.text.trim(),
                    'role': _userData?['role'] ?? 'user',
                    'updatedAt': FieldValue.serverTimestamp(),
                  };

                  try {
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .set(profile, SetOptions(merge: true));
                    try {
                      await user.updateDisplayName(profile['name'].toString());
                    } catch (_) {
                      // Firestore profile is the visible source of truth.
                    }
                    if (!mounted) return;
                    setState(() {
                      _userData = {
                        ...?_userData,
                        ...profile,
                        'phone':
                            profile['phone']!.toString().isEmpty
                                ? 'Not provided'
                                : profile['phone'],
                        'bloodGroup':
                            profile['bloodGroup']!.toString().isEmpty
                                ? 'Not provided'
                                : profile['bloodGroup'],
                        'bio': 'Patient',
                        'address':
                            profile['address']!.toString().isEmpty
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
    addressController.dispose();

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully.')),
      );
    }
  }

  Future<void> _pickProfilePhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _isUploadingPhoto) return;

    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 900,
      );
      if (pickedFile == null) return;

      setState(() => _isUploadingPhoto = true);
      final bytes = await pickedFile.readAsBytes();
      if (mounted) {
        setState(() => _profilePhotoPreviewBytes = bytes);
      }
      final safeName = _safeImageName(pickedFile.name);
      final storagePath =
          'profile_photos/${user.uid}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      final ref = FirebaseStorage.instance.ref(storagePath);
      final uploadTask = await ref.putData(
        bytes,
        SettableMetadata(contentType: _contentTypeFor(safeName)),
      );
      final photoUrl = await uploadTask.ref.getDownloadURL();
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'profilePhotoUrl': photoUrl,
        'profilePhotoStoragePath': storagePath,
        'bio': 'Patient',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _userData = {
          ...?_userData,
          'profilePhotoUrl': photoUrl,
          'profilePhotoStoragePath': storagePath,
          'bio': 'Patient',
        };
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile photo updated.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not upload profile photo.')),
      );
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  String _safeImageName(String imageName) {
    final value = imageName.trim().isEmpty ? 'profile.jpg' : imageName.trim();
    final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return sanitized.isEmpty ? 'profile.jpg' : sanitized;
  }

  String _contentTypeFor(String imageName) {
    final lowerName = imageName.toLowerCase();
    if (lowerName.endsWith('.png')) return 'image/png';
    if (lowerName.endsWith('.webp')) return 'image/webp';
    if (lowerName.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: LoadingWidget(),
      );
    }
    if (_userData == null) {
      return const EmptyStateWidget(message: 'No profile data found.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          title: 'Profile',
          subtitle: 'Manage your account information.',
        ),
        const SizedBox(height: 16),
        _UserPanel(
          child: Column(
            children: [
              _ProfilePhotoPicker(
                photoUrl: (_userData?['profilePhotoUrl'] ?? '').toString(),
                previewBytes: _profilePhotoPreviewBytes,
                isUploading: _isUploadingPhoto,
                onPickPhoto: _pickProfilePhoto,
              ),
              const SizedBox(height: 16),
              Text(
                _userData?['name'] ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _UserColors.navy,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _userData?['email'] ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _UserColors.muted),
              ),
              const SizedBox(height: 18),
              _ProfileDetail(label: 'Phone Number', value: _userData?['phone']),
              _ProfileDetail(
                label: 'Blood Group',
                value: _userData?['bloodGroup'],
              ),
              const _ProfileDetail(label: 'Bio', value: 'Patient'),
              _ProfileDetail(label: 'Address', value: _userData?['address']),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openEditProfileDialog,
                      icon: const Icon(Icons.edit_rounded),
                      label: const Text('Edit Profile'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _ActionCard(
          title: 'Logout',
          subtitle: 'Sign out from this device.',
          icon: Icons.logout_rounded,
          color: _UserColors.red,
          onTap: widget.onLogout,
        ),
      ],
    );
  }
}

class _ProfilePhotoPicker extends StatelessWidget {
  const _ProfilePhotoPicker({
    required this.photoUrl,
    required this.previewBytes,
    required this.isUploading,
    required this.onPickPhoto,
  });

  final String photoUrl;
  final Uint8List? previewBytes;
  final bool isUploading;
  final VoidCallback onPickPhoto;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl.trim().isNotEmpty;
    final preview = previewBytes;
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child:
                  preview != null
                      ? Image.memory(
                        preview,
                        width: 132,
                        height: 132,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      )
                      : hasPhoto
                      ? Image.network(
                        photoUrl,
                        width: 132,
                        height: 132,
                        fit: BoxFit.cover,
                        cacheWidth: 264,
                        cacheHeight: 264,
                        gaplessPlayback: true,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return _fallbackImage();
                        },
                        errorBuilder: (_, __, ___) => _fallbackImage(),
                      )
                      : _fallbackImage(),
            ),
            if (isUploading)
              Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.42),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: isUploading ? null : onPickPhoto,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: Text(hasPhoto ? 'Change Profile Photo' : 'Add Profile Photo'),
        ),
      ],
    );
  }

  Widget _fallbackImage() {
    return Image.asset(
      'assets/profiledemo.png',
      width: 132,
      height: 132,
      fit: BoxFit.cover,
    );
  }
}

class _SubmissionCard extends StatelessWidget {
  const _SubmissionCard({required this.record});

  final DatasetRecordModel record;

  @override
  Widget build(BuildContext context) {
    return _UserPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SoftIcon(
                icon: Icons.science_outlined,
                color: _UserColors.blue,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.kitDisplayName,
                      style: const TextStyle(
                        color: _UserColors.navy,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      record.submittedAtDigital,
                      style: const TextStyle(color: _UserColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusChip(label: record.reviewStatus, color: _UserColors.blue),
              _StatusChip(
                label: record.selectedResult,
                color:
                    record.selectedResult == 'Positive'
                        ? _UserColors.green
                        : _UserColors.red,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoLine(label: 'Selected Result', value: record.selectedResult),
          if (record.kitId.isNotEmpty)
            _InfoLine(label: 'Kit ID', value: record.kitId),
          _InfoLine(label: 'Kit Name', value: record.kitDisplayName),
          if (record.kitCategory.isNotEmpty)
            _InfoLine(label: 'Category', value: record.kitCategory),
          if (record.kitSampleType.isNotEmpty)
            _InfoLine(label: 'Sample Type', value: record.kitSampleType),
          if (record.kitManufacturer.isNotEmpty)
            _InfoLine(label: 'Manufacturer', value: record.kitManufacturer),
          if (record.kitDescription.isNotEmpty)
            _InfoLine(label: 'Description', value: record.kitDescription),
          if (record.imageUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                record.imageUrl,
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _InlineImageFallback(),
              ),
            ),
          ] else if (record.imageName.isNotEmpty) ...[
            const SizedBox(height: 10),
            const _InlineImageFallback(),
          ],
        ],
      ),
    );
  }
}

class _UserTopBar extends StatelessWidget {
  const _UserTopBar({required this.page});

  final _UserPage page;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 520;
    return Container(
      height: compact ? 86 : 104,
      padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF071B45), Color(0xFF0A2F66)],
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 54),
          Expanded(
            child: Text(
              page.title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 22 : 26,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 54),
        ],
      ),
    );
  }
}

class _UserBottomNav extends StatelessWidget {
  const _UserBottomNav({
    required this.pages,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_UserPage> pages;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: _UserColors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              for (final entry in pages.indexed)
                Expanded(
                  child: _UserBottomNavItem(
                    page: entry.$2,
                    selected: entry.$1 == selectedIndex,
                    onTap: () => onSelected(entry.$1),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserBottomNavItem extends StatelessWidget {
  const _UserBottomNavItem({
    required this.page,
    required this.selected,
    required this.onTap,
  });

  final _UserPage page;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? _UserColors.blue : const Color(0xFF606A80);
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(page.icon, color: color, size: selected ? 26 : 24),
            const SizedBox(height: 5),
            Text(
              page.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedUserBackground extends StatefulWidget {
  const _AnimatedUserBackground({required this.child});

  final Widget child;

  @override
  State<_AnimatedUserBackground> createState() =>
      _AnimatedUserBackgroundState();
}

class _AnimatedUserBackgroundState extends State<_AnimatedUserBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = _controller.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-0.9 + value * 0.6, -1),
              end: Alignment(0.8 - value * 0.4, 1),
              colors: const [
                Color(0xFFF8FAFD),
                Color(0xFFEFF7FF),
                Color(0xFFF7FFFC),
              ],
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _UserPanel extends StatelessWidget {
  const _UserPanel({this.title, this.child});

  final String? title;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.82),
        border: Border.all(color: _UserColors.border),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: const TextStyle(
                color: _UserColors.navy,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (child != null) child!,
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: _UserPanel(
        child: Row(
          children: [
            _SoftIcon(icon: icon, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _UserColors.navy,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: const TextStyle(color: _UserColors.muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _UserColors.muted),
          ],
        ),
      ),
    );
  }
}

class _UserPrimaryButton extends StatelessWidget {
  const _UserPrimaryButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        backgroundColor: Colors.white,
        foregroundColor: _UserColors.blue,
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _UserGhostButton extends StatelessWidget {
  const _UserGhostButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white, width: 1.4),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _SoftIcon extends StatelessWidget {
  const _SoftIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SoftIcon(icon: icon, color: _UserColors.blue),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _UserColors.navy,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: _UserColors.muted, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _UserColors.navy,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(subtitle, style: const TextStyle(color: _UserColors.muted)),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.22)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text.rich(
        TextSpan(
          text: '$label: ',
          style: const TextStyle(
            color: _UserColors.navy,
            fontWeight: FontWeight.w900,
          ),
          children: [
            TextSpan(
              text: value,
              style: const TextStyle(
                color: _UserColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileDetail extends StatelessWidget {
  const _ProfileDetail({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _UserColors.blue.withOpacity(0.045),
        border: Border.all(color: _UserColors.blue.withOpacity(0.12)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _UserColors.muted)),
          const SizedBox(height: 4),
          Text(
            (value ?? 'Not provided').toString(),
            style: const TextStyle(
              color: _UserColors.navy,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineImageFallback extends StatelessWidget {
  const _InlineImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _UserColors.blue.withOpacity(0.06),
        border: Border.all(color: _UserColors.blue.withOpacity(0.14)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Icon(Icons.image_outlined, size: 18, color: _UserColors.blue),
          SizedBox(width: 8),
          Text('Photo attached', style: TextStyle(color: _UserColors.muted)),
        ],
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

class _UserPage {
  const _UserPage(this.name, this.title, this.icon);

  final String name;
  final String title;
  final IconData icon;
}

class _UserColors {
  static const page = Color(0xFFF4F7FB);
  static const navy = Color(0xFF111D35);
  static const muted = Color(0xFF657086);
  static const border = Color(0xFFE2E6EF);
  static const blue = Color(0xFF137AC9);
  static const green = Color(0xFF14976A);
  static const red = Color(0xFFD04D4D);
}
