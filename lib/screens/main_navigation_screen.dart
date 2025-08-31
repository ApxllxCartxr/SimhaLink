import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:simha_link/screens/auth_wrapper.dart';


import 'package:simha_link/screens/group_creation_screen.dart';
import 'package:simha_link/screens/map_screen.dart';
import 'package:simha_link/screens/profile_screen.dart';
import 'package:simha_link/screens/group_chat_screen.dart';
import 'package:simha_link/services/auth_service.dart';
import 'package:simha_link/services/emergency_communication_service.dart';
import 'package:simha_link/utils/user_preferences.dart';
 

/// Main navigation container with a bottom navigation bar
/// Handles routing between main screens and maintaining navigation state
class MainNavigationScreen extends StatefulWidget {
  final String groupId;
  
  const MainNavigationScreen({
    super.key,
    required this.groupId,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  late String _groupId;
  // _userRole removed - role-specific UI now handled elsewhere
  bool _isLoading = true;
  bool _isLeavingGroup = false;
  bool _isLoggingOut = false;
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _groupId = widget.groupId;
    _getUserRole();
    // Aggressive fallback: listen for global auth state changes and
    // force navigation to the auth wrapper when the user signs out.
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        // Ensure this runs after the current frame to avoid navigation during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          try {
            Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const AuthWrapper()),
              (_) => false,
            );
          } catch (_) {
            // ignore navigation errors - this is a best-effort fallback
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _getUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Check if it's a narrow screen (like a phone)
    final isPhone = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: _selectedIndex,
              children: [
                // Profile (left)
                const ProfileScreen(),

                // Map (middle)
                MapScreen(groupId: _groupId),

                // Group Chat (right)
                GroupChatScreen(groupId: _groupId),
              ],
            ),
      bottomNavigationBar: isPhone
          ? _buildBottomNavigationBar()
          : null,
      floatingActionButton: isPhone
          ? null // We're using the bottom nav for navigation
          : _buildFloatingActionButtons(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      endDrawer: _buildDrawer(),
    );
  }

  Widget _buildBottomNavigationBar() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: _onItemTapped,
      selectedItemColor: Colors.red,
      unselectedItemColor: Colors.grey,
      items: [
        const BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: 'Profile',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.map),
          label: 'Map',
        ),
        BottomNavigationBarItem(
          icon: _buildBadgedIcon(
            icon: Icons.chat,
            stream: EmergencyCommunicationService.getUnreadCountStream(),
          ),
          label: 'Chat',
        ),
      ],
    );
  }

  Widget _buildBadgedIcon({
    required IconData icon,
    required Stream<int> stream,
  }) {
    return StreamBuilder<int>(
      stream: stream,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon),
            if (count > 0)
              Positioned(
                right: -8,
                top: -5,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget? _buildFloatingActionButtons() {
    // For tablet/desktop layout
    return null; // Would implement a floating action menu here
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(
              color: Colors.red.shade800,
            ),
            accountName: const Text('User Name'), // Would get from Firebase
            accountEmail: Text(FirebaseAuth.instance.currentUser?.email ?? ''),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                FirebaseAuth.instance.currentUser?.email?.substring(0, 1).toUpperCase() ?? '',
                style: TextStyle(
                  fontSize: 24,
                  color: Colors.red.shade800,
                ),
              ),
            ),
          ),
          
          // Menu items
          ListTile(
            leading: const Icon(Icons.map),
            title: const Text('Map'),
            selected: _selectedIndex == 0,
            onTap: () {
              Navigator.pop(context);
              _onItemTapped(0);
            },
          ),
          
          ListTile(
            leading: const Icon(Icons.group),
            title: const Text('Group Info'),
            onTap: () {
              Navigator.pop(context);
              // Would navigate to group info
            },
          ),
          
          const Divider(),
          
          ListTile(
            leading: const Icon(Icons.exit_to_app),
            title: const Text('Leave Group'),
            onTap: () {
              Navigator.pop(context);
              _showLeaveGroupConfirmation();
            },
          ),
          
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: () {
              Navigator.pop(context);
              _showLogoutConfirmation();
            },
          ),
          
          const Divider(),
          
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('About'),
            onTap: () {
              Navigator.pop(context);
              // Would show about dialog
            },
          ),
        ],
      ),
    );
  }

  void _showLeaveGroupConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Group?'),
        content: const Text(
          'You will be removed from this group and will need to create or join a new group.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: _handleLeaveGroup,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('LEAVE GROUP'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLeaveGroup() async {
    if (_isLeavingGroup) return;
    
    setState(() {
      _isLeavingGroup = true;
    });
    
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('Leaving group...'),
            ],
          ),
        ),
      );
      
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Navigator.pop(context); // Close loading dialog
        return;
      }
      
      // Leave group and clean up
      await UserPreferences.leaveGroupAndCleanup(_groupId, user.uid);
      
      if (mounted) {
        // Close loading dialog
        Navigator.pop(context);
        
        // IMPORTANT: Use direct navigation instead of named routes
        // This avoids conditional rendering which can cause navigation issues
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const GroupCreationScreen()),
        );
      }
    } catch (e) {
      // Handle errors
      if (mounted) {
        // Close loading dialog if open
        Navigator.pop(context);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error leaving group: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLeavingGroup = false;
        });
      }
    }
  }

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout?'),
        content: const Text(
          'You will be signed out of your account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: _handleLogout,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('LOGOUT'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    if (_isLoggingOut) return;
    
    setState(() {
      _isLoggingOut = true;
    });
    
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('Logging out...'),
            ],
          ),
        ),
      );
      
      // Sign out (uses AuthService for proper cleanup)
      await AuthService().signOut();
      
      // Force reset to login screen using root navigator
      if (mounted) {
        // Pop the dialog first
        Navigator.of(context, rootNavigator: true).pop();
        
        // Completely clear the navigation stack and show the AuthWrapper
        // (AuthWrapper will read auth state and show the correct screen).
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthWrapper()),
          (_) => false, // Remove all routes
        );
      }
    } catch (e) {
      // Handle errors
      if (mounted) {
        // Close loading dialog if open
        Navigator.of(context, rootNavigator: true).pop();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error logging out: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
        });
      }
    }
  }
}
