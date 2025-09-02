import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:simha_link/services/state_sync_service.dart';
import 'package:simha_link/services/fcm_service.dart';
import 'package:simha_link/utils/user_preferences.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Track logout state to prevent multiple calls
  bool _isSigningOut = false;

  // Stream of authentication state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  
  // Current user
  User? get currentUser => _auth.currentUser;
  
  // Check if user is signed in
  bool get isSignedIn => currentUser != null;

  /// Sign in with email and password
  Future<UserCredential?> signInWithEmailPassword(
    String email,
    String password,
  ) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Update last sign-in time in Firestore
      if (credential.user != null) {
        await _updateUserLastSignIn(credential.user!);
      }
      
      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw Exception('Sign in failed: $e');
    }
  }

  /// Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return null; // User cancelled the sign-in
      }

      final GoogleSignInAuthentication googleAuth = 
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      
      // Create or update user profile in Firestore
      if (userCredential.user != null) {
        await _createOrUpdateUserProfile(userCredential.user!);
      }
      
      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw Exception('Google sign in failed: $e');
    }
  }

  /// Register with email and password
  Future<UserCredential?> registerWithEmailPassword(
    String email,
    String password,
    String displayName,
  ) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Update display name
      await credential.user?.updateDisplayName(displayName);
      
      // Create user profile in Firestore
      if (credential.user != null) {
        await _createOrUpdateUserProfile(credential.user!);
      }
      
      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw Exception('Registration failed: $e');
    }
  }

  /// Sign out
  Future<void> signOut() async {
    if (_isSigningOut) {
      print('⚠️ Sign out already in progress, skipping...');
      return; // Prevent multiple logout calls
    }
    
    try {
      _isSigningOut = true;
      print('🚪 Starting sign out process...');
      
      // Get current user before signing out
      final currentUser = _auth.currentUser;
      
      // IMPORTANT: We need to preserve the group ID so when user logs back in,
      // they don't have to rejoin a group
      if (currentUser != null) {
        try {
          final groupId = await UserPreferences.getUserGroupId();
          print('💾 Preserving group ID for user ${currentUser.uid}: $groupId');
          
          // Extra safety: Verify and save the group ID again to ensure it persists
          if (groupId != null && groupId.isNotEmpty) {
            await UserPreferences.setUserGroupId(groupId);
            print('✅ Re-saved group ID before logout: $groupId');
          } else {
            print('⚠️ No group ID found to preserve before logout');
          }
        } catch (e) {
          print('⚠️ Error preserving group ID: $e');
        }
      }
      
      // First clean up FCM subscriptions
      try {
        await FCMService.cleanup();
        print('✅ FCM cleanup successful');
      } catch (e) {
        print('⚠️ FCM cleanup error (continuing with logout): $e');
        // Don't block logout if FCM cleanup fails
      }
      
      // Then sign out from auth providers
      try {
        await _googleSignIn.signOut();
        print('✅ Google Sign-In logout successful');
      } catch (e) {
        print('⚠️ Google Sign-In logout error: $e');
        // Continue with Firebase logout even if Google logout fails
      }
      
      // Finally sign out from Firebase
      await _auth.signOut();
      print('✅ Firebase Auth logout successful');
      
      // Dispose state sync service on logout
      StateSyncService.dispose();
      
      print('✅ Sign out successful - Firebase auth cleared, group data preserved');
      
      // Add a small delay to ensure auth state propagates
      await Future.delayed(const Duration(milliseconds: 300));
      
    } catch (e) {
      print('❌ Sign out failed: $e');
      throw Exception('Sign out failed: $e');
    } finally {
      _isSigningOut = false;
      print('🔄 Sign out process completed');
    }
  }

  /// Reset password
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw Exception('Password reset failed: $e');
    }
  }

  /// Delete user account
  Future<void> deleteAccount() async {
    try {
      final user = currentUser;
      if (user != null) {
        // Delete user data from Firestore
        await _firestore.collection('users').doc(user.uid).delete();
        
        // Delete the auth account
        await user.delete();
      }
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw Exception('Account deletion failed: $e');
    }
  }

  /// Create or update user profile in Firestore
  Future<void> _createOrUpdateUserProfile(User user) async {
    try {
      final userDoc = _firestore.collection('users').doc(user.uid);
      final docSnapshot = await userDoc.get();
      
      final userData = {
        'email': user.email,
        'displayName': user.displayName,
        'photoURL': user.photoURL,
        'lastSignIn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      if (!docSnapshot.exists) {
        // Create new user profile
        userData['createdAt'] = FieldValue.serverTimestamp();
        userData['role'] = 'participant'; // Default role
        await userDoc.set(userData);
      } else {
        // Update existing profile
        await userDoc.update(userData);
      }
    } catch (e) {
      // Don't throw here as auth was successful
      print('Failed to update user profile: $e');
    }
  }

  /// Update user last sign-in time
  Future<void> _updateUserLastSignIn(User user) async {
    try {
      await _firestore.collection('users').doc(user.uid).update({
        'lastSignIn': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Don't throw here as auth was successful
      print('Failed to update last sign-in: $e');
    }
  }

  /// Get a proper display name for a user
  static String getUserDisplayName(User? user) {
    if (user == null) return 'Guest';
    
    // Try display name first
    if (user.displayName != null && user.displayName!.trim().isNotEmpty) {
      return user.displayName!.trim();
    }
    
    // Fall back to email username (part before @)
    if (user.email != null) {
      final emailParts = user.email!.split('@');
      if (emailParts.isNotEmpty && emailParts[0].isNotEmpty) {
        // Capitalize first letter and make it more readable
        final username = emailParts[0];
        return username.substring(0, 1).toUpperCase() + 
               username.substring(1).toLowerCase();
      }
    }
    
    // Last resort
    return 'User';
  }

  /// Get user display name from Firestore (async version with better fallback)
  static Future<String> getUserDisplayNameFromFirestore(User? user) async {
    if (user == null) return 'Guest';
    
    try {
      // First, check Firestore for stored displayName
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
          
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final storedName = userData['displayName'] as String?;
        if (storedName != null && storedName.trim().isNotEmpty) {
          return storedName.trim();
        }
      }
    } catch (e) {
      print('Error fetching user name from Firestore: $e');
    }
    
    // Fall back to the sync version
    return getUserDisplayName(user);
  }

  /// Get a proper display name for current user
  static String getCurrentUserDisplayName() {
    return getUserDisplayName(FirebaseAuth.instance.currentUser);
  }
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No user found with this email address.';
      case 'wrong-password':
        return 'Wrong password provided.';
      case 'email-already-in-use':
        return 'An account already exists with this email address.';
      case 'weak-password':
        return 'The password provided is too weak.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many requests. Please try again later.';
      case 'operation-not-allowed':
        return 'This operation is not allowed.';
      default:
        return 'Authentication error: ${e.message}';
    }
  }
}
