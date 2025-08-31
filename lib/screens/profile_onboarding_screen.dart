import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileOnboardingScreen extends StatefulWidget {
  const ProfileOnboardingScreen({super.key});

  @override
  State<ProfileOnboardingScreen> createState() => _ProfileOnboardingScreenState();
}

class _ProfileOnboardingScreenState extends State<ProfileOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String _role = 'Attendee';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _nameController.text = user.displayName ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No authenticated user');

      final displayName = _nameController.text.trim();

      // Update Firebase Auth display name
      try {
        await user.updateDisplayName(displayName);
      } catch (_) {}

      // Update/create Firestore user doc
      final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      await userRef.set({
        'displayName': displayName,
        'role': _role,
        'email': user.email,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save profile: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complete your profile')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Display name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a display name' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _role,
                items: const [
                  DropdownMenuItem(value: 'Attendee', child: Text('Attendee')),
                  DropdownMenuItem(value: 'Volunteer', child: Text('Volunteer')),
                  DropdownMenuItem(value: 'Organizer', child: Text('Organizer')),
                  DropdownMenuItem(value: 'VIP', child: Text('VIP')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _role = v);
                },
                decoration: const InputDecoration(labelText: 'Role'),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      child: _isSaving ? const CircularProgressIndicator() : const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Show onboarding as a modal dialog. Returns true if the user saved their profile.
Future<bool?> showProfileOnboardingDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final _formKey = GlobalKey<FormState>();
      final _nameController = TextEditingController(text: FirebaseAuth.instance.currentUser?.displayName ?? '');
      String _role = 'Attendee';
      bool _isSaving = false;

      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> _saveProfile() async {
            if (!_formKey.currentState!.validate()) return;
            setState(() => _isSaving = true);

            try {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) throw Exception('No authenticated user');

              final displayName = _nameController.text.trim();

              try {
                await user.updateDisplayName(displayName);
              } catch (_) {}

              final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
              await userRef.set({
                'displayName': displayName,
                'role': _role,
                'email': user.email,
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));

              if (context.mounted) Navigator.of(context).pop(true);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save profile: $e')));
              }
            } finally {
              if (context.mounted) setState(() => _isSaving = false);
            }
          }

          return AlertDialog(
            title: const Text('Complete your profile'),
            content: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Display name'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a display name' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _role,
                      items: const [
                        DropdownMenuItem(value: 'Attendee', child: Text('Attendee')),
                        DropdownMenuItem(value: 'Volunteer', child: Text('Volunteer')),
                        DropdownMenuItem(value: 'Organizer', child: Text('Organizer')),
                        DropdownMenuItem(value: 'VIP', child: Text('VIP')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _role = v);
                      },
                      decoration: const InputDecoration(labelText: 'Role'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Skip')),
              ElevatedButton(
                onPressed: _isSaving ? null : _saveProfile,
                child: _isSaving ? const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)) : const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );
}
