
import 'dart:io' show Platform;
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'ecg_data_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'main_tab_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isLoading = false;

  // ── Navigation ────────────────────────────────────────────────────

  Future<void> _fetchAndNavigate(String token) async {
    try {
      final url = Uri.parse('http://35.216.60.242:9101/user/self');
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print("서버 응답 상태코드: ${response.statusCode}");
      print("서버 응답 내용: ${response.body}");

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        final userData = responseData['data'];

        await _syncUserData(userData);

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MainTabPage()),
          );
        }
      } else {
        throw Exception("Failed to fetch user info from the server.");
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _syncUserData(Map<String, dynamic> data) async {
    final ecgService = Provider.of<EcgDataService>(context, listen: false);
    final prefs = await SharedPreferences.getInstance();

    String name = data['name'] ?? 'Unknown';
    await prefs.setString('username', name);
    ecgService.setUserName(name);

    if (data['address'] != null) {
      await prefs.setString('address', data['address']);
      ecgService.setAddress(data['address']);
    }
    if (data['phone'] != null) {
      await prefs.setString('phoneNumber', data['phone']);
      ecgService.setPhoneNumber(data['phone']);
    }
    if (data['detail_address'] != null) {
      await prefs.setString('detailedAddress', data['detail_address']);
      ecgService.setDetailedAddress(data['detail_address']);
    }
    await prefs.setBool('isSurveyCompleted', data['onboarded'] ?? false);
  }

  // ── Google Login ──────────────────────────────────────────────────

  Future<void> _handleGoogleLogin() async {
    setState(() => _isLoading = true);
    try {
      final String? idToken = await _signInWithGoogle();
      if (idToken != null && mounted) {
        await _fetchAndNavigate(idToken);
      }
    } catch (e) {
      debugPrint("Google login error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("An error occurred during Google sign-in: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String?> _signInWithGoogle() async {
    // Web client ID for server-side token verification
    const webClientId = '393654640908-tuhebsgvtf7j8vkouqjjvrunjn0rn8nb.apps.googleusercontent.com';
    // iOS client ID — required on iOS without GoogleService-Info.plist
    const iosClientId = '393654640908-8k1bq7vat42ttaj6m2d887ge0rpriung.apps.googleusercontent.com';

    final googleUser = await GoogleSignIn(
      clientId: Platform.isIOS ? iosClientId : null,
      serverClientId: webClientId,
    ).signIn();

    final googleAuth = await googleUser?.authentication;
    if (googleAuth == null) return null;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);
    final user = userCredential.user;
    if (user == null) return null;

    if (user.displayName?.isNotEmpty == true) {
      onLoginComplete(user.displayName!);
    }
    // Return Firebase ID token (not Google's), as the server validates against Firebase
    return await user.getIdToken(true);
  }

  // ── Apple Login ───────────────────────────────────────────────────

  Future<void> _handleAppleLogin() async {
    setState(() => _isLoading = true);
    try {
      final String? idToken = await _signInWithApple();
      if (idToken != null && mounted) {
        await _fetchAndNavigate(idToken);
      }
    } catch (e) {
      debugPrint("Apple login error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("An error occurred during Apple sign-in: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _generateNonce([int length = 32]) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<String?> _signInWithApple() async {
    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);

    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );

    final oauthCredential = OAuthProvider("apple.com").credential(
      idToken: appleCredential.identityToken,
      accessToken: appleCredential.authorizationCode,
      rawNonce: rawNonce,
    );

    final userCredential = await _auth.signInWithCredential(oauthCredential);
    final user = userCredential.user;
    if (user == null) return null;

    if (user.displayName?.isNotEmpty == true) {
      onLoginComplete(user.displayName!);
    }
    // Return Firebase ID token so the server can verify it
    return await user.getIdToken(true);
  }

  void onLoginComplete(String name) {
    Provider.of<EcgDataService>(context, listen: false).setUserName(name);
  }

  // ── UI ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 80),
                  Image.asset('assets/icon/img.png', width: 200, height: 200),
                  const SizedBox(height: 40),

                  if (!Platform.isIOS) const SizedBox(height: 56),

                  // Google 로그인 버튼
                  _SocialLoginButton(
                    onPressed: _handleGoogleLogin,
                    logo: Image.asset(
                      'assets/icon/google_logo.png',
                      height: 24,
                      width: 24,
                    ),
                    label: 'Sign in with Google',
                  ),

                  // Apple 로그인 버튼 (iOS 전용, Google 버튼과 동일 디자인)
                  if (Platform.isIOS) ...[
                    const SizedBox(height: 12),
                    _SocialLoginButton(
                      onPressed: _handleAppleLogin,
                      // U+F8FF → Apple logo character in iOS system font
                      logo: const Text(
                        '',
                        style: TextStyle(fontSize: 22, color: Colors.black87),
                      ),
                      label: 'Sign in with Apple',
                    ),
                  ],

                  const SizedBox(height: 20),
                  Container(width: double.infinity, height: 1, color: Colors.black12),
                  const Text(
                    "© 2025 XALUTE Health. All rights reserved.",
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),

          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.4),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Shared button widget ──────────────────────────────────────────────

class _SocialLoginButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget logo;
  final String label;

  const _SocialLoginButton({
    required this.onPressed,
    required this.logo,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        minimumSize: const Size(double.infinity, 56),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFFE0E0E0), width: 1),
        ),
        elevation: 0,
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          logo,
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
