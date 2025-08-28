import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:simha_link/utils/user_preferences.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _auth = FirebaseAuth.instance;
  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  
  late TabController _tabController;
  
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  // Role selection for signup
  String _selectedRole = 'Attendee'; // Default role
  final List<String> _roles = ['Attendee', 'Volunteer', 'Organizer'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _isLogin = _tabController.index == 0;
      });
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    print('🔄 Setting loading state to true');
    setState(() {
      _isLoading = true;
    });

    try {
      print('🚀 Starting authentication process...');
      
      if (_isLogin) {
        print('📧 Attempting login with email: ${_emailController.text.trim()}');
        UserCredential userCredential = await _auth.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        print('✅ Login successful: ${userCredential.user?.uid}');
        
        // For existing users, check their role and ensure proper group assignment
        await _handleExistingUserLogin(userCredential.user!);
      } else {
        print('📝 Attempting registration with email: ${_emailController.text.trim()}');
        UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        print('✅ Registration successful: ${userCredential.user?.uid}');
        
        // Save user role and handle group assignment
        await _handleUserRoleAndGroup(userCredential.user!);
      }
      
      if (mounted) {
        print('🎯 Authentication completed successfully - AuthWrapper will handle navigation');
        // The AuthWrapper will automatically handle navigation via StreamBuilder
        // No need to manually navigate here
      }
    } on FirebaseAuthException catch (e) {
      print('❌ Auth error: ${e.code} - ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_getAuthErrorMessage(e)),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      print('❌ Unexpected error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An unexpected error occurred: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        print('🔄 Setting loading state to false');
        setState(() {
          _isLoading = false;
        });
      } else {
        print('⚠️ Widget not mounted, skipping loading state reset');
      }
    }
  }

  String _getAuthErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No user found with this email address.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please try again later.';
      case 'email-already-in-use':
        return 'An account already exists with this email address.';
      case 'weak-password':
        return 'Password is too weak. Please choose a stronger password.';
      case 'network-request-failed':
        return 'Network error. Please check your connection and try again.';
      default:
        return e.message ?? 'An authentication error occurred.';
    }
  }

  Future<void> _handleExistingUserLogin(User user) async {
    try {
      // Check if user has a role saved in Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data()!;
        final userRole = userData['role'] as String?;

        if (userRole == 'Volunteer') {
          final groupId = await _ensureSpecialGroupExists('volunteers', 'Volunteers');
          await UserPreferences.setUserGroupId(groupId);
          
          // Ensure user is in the volunteers group
          await FirebaseFirestore.instance
              .collection('groups')
              .doc(groupId)
              .update({
            'memberIds': FieldValue.arrayUnion([user.uid])
          });
        } else if (userRole == 'Organizer') {
          final groupId = await _ensureSpecialGroupExists('organizers', 'Organizers');
          await UserPreferences.setUserGroupId(groupId);
          
          // Ensure user is in the organizers group
          await FirebaseFirestore.instance
              .collection('groups')
              .doc(groupId)
              .update({
            'memberIds': FieldValue.arrayUnion([user.uid])
          });
        }
        // For attendees or users without roles, let AuthWrapper handle group logic
      }
    } catch (e) {
      print('Error handling existing user login: $e');
      // If there's an error, let AuthWrapper handle the navigation
    }
  }

  Future<void> _handleUserRoleAndGroup(User user) async {
    try {
      // Save user profile with role in Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'uid': user.uid,
        'email': user.email,
        'role': _selectedRole,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Handle group assignment based on role
      String groupId;
      if (_selectedRole == 'Volunteer') {
        groupId = await _ensureSpecialGroupExists('volunteers', 'Volunteers');
        // Set the user's group
        await UserPreferences.setUserGroupId(groupId);
        
        // Add user to the group's member list
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(groupId)
            .update({
          'memberIds': FieldValue.arrayUnion([user.uid])
        });
      } else if (_selectedRole == 'Organizer') {
        groupId = await _ensureSpecialGroupExists('organizers', 'Organizers');
        // Set the user's group
        await UserPreferences.setUserGroupId(groupId);
        
        // Add user to the group's member list
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(groupId)
            .update({
          'memberIds': FieldValue.arrayUnion([user.uid])
        });
      } else {
        // Attendees don't get auto-assigned to a group
        // Clear any existing group preferences to ensure clean state
        await UserPreferences.clearGroupData();
        print('🎫 New attendee - cleared group data, will show group creation');
        return; // Will go to group creation screen
      }

    } catch (e) {
      print('Error handling user role and group: $e');
      // If there's an error, user will go to group creation screen
    }
  }

  Future<String> _ensureSpecialGroupExists(String groupId, String groupName) async {
    final groupRef = FirebaseFirestore.instance.collection('groups').doc(groupId);
    final groupDoc = await groupRef.get();

    if (!groupDoc.exists) {
      // Create the special group
      await groupRef.set({
        'id': groupId,
        'name': groupName,
        'type': 'special', // Mark as special group
        'createdAt': FieldValue.serverTimestamp(),
        'memberIds': [],
        'joinCode': '', // Special groups don't need join codes
      });
    }

    return groupId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Stack(
        children: [
          // Grid Background
          CustomPaint(
            painter: GridPainter(),
            size: Size.infinite,
          ),
          // Main Content
          Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo and Title
                    const Text(
                      'Simha Link',
                      style: TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Connect. Collaborate. Create.',
                      style: TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 16,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 48),
                    
                    // Auth Container
                    Container(
                      width: 400,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Tab Bar
                          TabBar(
                            controller: _tabController,
                            tabs: const [
                              Tab(text: 'Login'),
                              Tab(text: 'Sign Up'),
                            ],
                          ),
                          const SizedBox(height: 24),
                          
                          // Form
                          Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                TextFormField(
                                  controller: _emailController,
                                  decoration: const InputDecoration(
                                    labelText: 'Email',
                                    prefixIcon: Icon(Icons.email),
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter your email';
                                    }
                                    if (!value.contains('@')) {
                                      return 'Please enter a valid email';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _passwordController,
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    prefixIcon: const Icon(Icons.lock),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                    ),
                                    border: const OutlineInputBorder(),
                                  ),
                                  obscureText: _obscurePassword,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter your password';
                                    }
                                    if (!_isLogin && value.length < 6) {
                                      return 'Password must be at least 6 characters';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                
                                // Role selection for signup only
                                if (!_isLogin) ...[
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Theme.of(context).dividerColor),
                                      borderRadius: BorderRadius.circular(8),
                                      color: Theme.of(context).cardColor,
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Select your role:',
                                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        ..._roles.map((role) => RadioListTile<String>(
                                          title: Text(
                                            role,
                                            style: Theme.of(context).textTheme.bodyLarge,
                                          ),
                                          value: role,
                                          groupValue: _selectedRole,
                                          onChanged: (value) {
                                            setState(() {
                                              _selectedRole = value!;
                                            });
                                          },
                                          contentPadding: EdgeInsets.zero,
                                          dense: true,
                                          activeColor: Theme.of(context).primaryColor,
                                        )),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                
                                const SizedBox(height: 24),
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : () {
                                      print('🔘 Button pressed - Loading: $_isLoading');
                                      _submitForm();
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.black,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor: Colors.grey,
                                      disabledForegroundColor: Colors.white,
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Text(
                                            _isLogin ? 'Login' : 'Sign Up',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.05)
      ..strokeWidth = 1;

    const spacing = 30.0;

    for (double i = 0; i < size.width; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }

    for (double i = 0; i < size.height; i += spacing) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
