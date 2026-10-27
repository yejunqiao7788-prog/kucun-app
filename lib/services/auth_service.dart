import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_profile.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  User? _currentUser;
  UserProfile? _currentProfile;
  bool _isLoading = false;
  String? _errorMessage;

  User? get currentUser => _currentUser;
  UserProfile? get currentProfile => _currentProfile;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _currentUser != null;

  AuthService() {
    _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  Future<void> _onAuthStateChanged(User? user) async {
    _currentUser = user;
    if (user != null) {
      await loadUserProfile(user.uid);
    } else {
      _currentProfile = null;
    }
    notifyListeners();
  }

  Future<void> loadUserProfile(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        _currentProfile = UserProfile.fromFirestore(doc.data()!, doc.id);
      } else {
        // Create initial default profile for new user
        final newProfile = UserProfile(
          id: uid,
          email: _currentUser?.email ?? '',
          username: _currentUser?.displayName ?? _currentUser?.email?.split('@').first ?? '用户',
          tenantId: 'tenant_${uid.substring(0, 8)}',
          tenantName: '我的仓库',
          subscriptionStatus: 'trial',
          subscriptionExpired: false,
          role: 'tenant_admin',
          status: 'active',
          permissions: {
            'dashboard': true,
            'products': true,
            'inventory': true,
            'orders': true,
            'showrooms': true,
            'ai': true,
            'finance': true,
          },
          currencySymbol: '₴',
        );
        await _firestore.collection('users').doc(uid).set(newProfile.toFirestore());
        _currentProfile = newProfile;
      }
    } catch (e) {
      debugPrint("Error loading user profile: $e");
    }
    notifyListeners();
  }

  // 1. Email & Password Sign In
  Future<bool> signInWithEmail(String email, String password) async {
    _setLoading(true);
    _clearError();
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      if (credential.user != null) {
        await loadUserProfile(credential.user!.uid);
        _setLoading(false);
        return true;
      }
    } on FirebaseAuthException catch (e) {
      _setError(_getAuthErrorMessage(e.code));
    } catch (e) {
      _setError(e.toString());
    }
    _setLoading(false);
    return false;
  }

  // 2. Email & Password Register
  Future<bool> registerWithEmail(String email, String password, String username, String tenantName) async {
    _setLoading(true);
    _clearError();
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      if (credential.user != null) {
        final uid = credential.user!.uid;
        final profile = UserProfile(
          id: uid,
          email: email.trim(),
          username: username.trim(),
          tenantId: 'tenant_${uid.substring(0, 8)}',
          tenantName: tenantName.trim().isNotEmpty ? tenantName.trim() : '默认租户',
          subscriptionStatus: 'trial',
          subscriptionExpired: false,
          role: 'tenant_admin',
          status: 'active',
          permissions: {
            'dashboard': true,
            'products': true,
            'inventory': true,
            'orders': true,
            'showrooms': true,
            'ai': true,
            'finance': true,
          },
          currencySymbol: '₴',
        );
        await _firestore.collection('users').doc(uid).set(profile.toFirestore());
        _currentProfile = profile;
        _setLoading(false);
        return true;
      }
    } on FirebaseAuthException catch (e) {
      _setError(_getAuthErrorMessage(e.code));
    } catch (e) {
      _setError(e.toString());
    }
    _setLoading(false);
    return false;
  }

  // 3. Google Sign-In
  Future<bool> signInWithGoogle() async {
    _setLoading(true);
    _clearError();
    try {
      UserCredential? credential;
      if (kIsWeb) {
        final GoogleAuthProvider authProvider = GoogleAuthProvider();
        credential = await _auth.signInWithPopup(authProvider);
      } else {
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          _setLoading(false);
          return false;
        }
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final AuthCredential cred = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        credential = await _auth.signInWithCredential(cred);
      }

      if (credential.user != null) {
        await loadUserProfile(credential.user!.uid);
        _setLoading(false);
        return true;
      }
    } on FirebaseAuthException catch (e) {
      _setError(_getAuthErrorMessage(e.code));
    } catch (e) {
      _setError(e.toString());
    }
    _setLoading(false);
    return false;
  }

  // 4. Phone Authentication
  Future<void> verifyPhone({
    required String phoneNumber,
    required Function(String verificationId, int? resendToken) onCodeSent,
    required Function(String error) onVerificationFailed,
    required Function(PhoneAuthCredential credential) onAutoVerified,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber.trim(),
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          _setLoading(false);
          onAutoVerified(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          _setLoading(false);
          final msg = _getAuthErrorMessage(e.code);
          _setError(msg);
          onVerificationFailed(msg);
        },
        codeSent: (String verificationId, int? resendToken) {
          _setLoading(false);
          onCodeSent(verificationId, resendToken);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _setLoading(false);
        },
      );
    } catch (e) {
      _setLoading(false);
      _setError(e.toString());
      onVerificationFailed(e.toString());
    }
  }

  Future<bool> signInWithPhoneCode(String verificationId, String smsCode) async {
    _setLoading(true);
    _clearError();
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode.trim(),
      );
      final userCred = await _auth.signInWithCredential(credential);
      if (userCred.user != null) {
        await loadUserProfile(userCred.user!.uid);
        _setLoading(false);
        return true;
      }
    } on FirebaseAuthException catch (e) {
      _setError(_getAuthErrorMessage(e.code));
    } catch (e) {
      _setError(e.toString());
    }
    _setLoading(false);
    return false;
  }

  // Sign out
  Future<void> signOut() async {
    try {
      if (!kIsWeb) {
        try {
          await _googleSignIn.signOut();
        } catch (_) {}
      }
      await _auth.signOut();
      _currentUser = null;
      _currentProfile = null;
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String msg) {
    _errorMessage = msg;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
  }

  String _getAuthErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return '用户不存在，请检查邮箱或先注册';
      case 'wrong-password':
        return '密码错误，请重新输入';
      case 'invalid-email':
        return '邮箱格式不正确';
      case 'user-disabled':
        return '该账号已被禁用';
      case 'email-already-in-use':
        return '该邮箱已被注册，请直接登录';
      case 'weak-password':
        return '密码强度不足，请使用至少6位密码';
      case 'invalid-verification-code':
        return '验证码不正确，请重新输入';
      case 'session-expired':
        return '验证码已过期，请重新获取';
      case 'too-many-requests':
        return '请求过于频繁，请稍后再试';
      default:
        return '认证失败: $code';
    }
  }
}
