import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isLoading = false;

  Future<void> _handleGoogleLogin() async {
    setState(() {
      _isLoading = true;
    });

    final prefs = await SharedPreferences.getInstance();
    bool isSurveyCompleted = prefs.getBool('isSurveyCompleted') ?? false;
    
    try {
      final String? idToken = await signInAndGetIdToken();

      if (idToken != null) {
        if(isSurveyCompleted) {
          Navigator.pushReplacementNamed(context, '/ecg');
        } else{
          Navigator.pushReplacementNamed(context, '/survey');
        }
      } else {
        debugPrint("Error: Firebase ID Token 획득 실패.");
      }

    } catch (e) {
      debugPrint("Google login error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }


  Future<String?> signInAndGetIdToken() async {

    String? webClientId = '393654640908-tuhebsgvtf7j8vkouqjjvrunjn0rn8nb.apps.googleusercontent.com';
    final GoogleSignInAccount? googleUser = await GoogleSignIn(
      serverClientId: webClientId,
    ).signIn();
    final GoogleSignInAuthentication? googleAuth = await googleUser?.authentication;

    if (googleAuth == null) return null;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final UserCredential userCredential = await _auth.signInWithCredential(credential);
    final User? user = userCredential.user;
    final String? idToken = googleAuth.idToken;


    if (user != null) {
      for (final providerProfile in user.providerData) {
        // ID of the provider (google.com, apple.com, etc.)
        final provider = providerProfile.providerId;
        // UID specific to the provider
        final uid = providerProfile.uid;
        // Name, email address, and profile photo URL
        final name = providerProfile.displayName;
        final emailAddress = providerProfile.email;
        final profilePhoto = providerProfile.photoURL;
      }
      return idToken;
    }
    return null;
  }
  Future<String?> signInWithApple() async {
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );

    // 이 identityToken이 바로 애플의 idToken입니다.
    final String? idToken = appleCredential.identityToken;

    if (idToken != null) {
      // Firebase 연결 (이 과정은 구글과 동일)
      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: idToken,
        accessToken: appleCredential.authorizationCode,
      );
      await _auth.signInWithCredential(oauthCredential);

      // 폰에서 서버나 워치로 보낼 '증명서'인 토큰을 반환합니다.
      return idToken;
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // 배경 흰색으로 변경
      body: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [

                  const SizedBox(height: 80),
                  // 요청하신 이미지 삽입
                  Image.asset(
                    'assets/icon/img.png',
                    width: 200, // 크기는 적절히 조절하세요
                    height: 200,
                  ),
                  const SizedBox(height: 40),

                  if (!Platform.isIOS)
                    const SizedBox(height: 56),

                  // Google 로그인 버튼
                  ElevatedButton(
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
                    onPressed: _handleGoogleLogin,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Image(
                          image: NetworkImage(
                              'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/512px-Google_%22G%22_logo.svg.png'),
                          height: 24.0,
                          width: 24.0,
                        ),
                        Text(
                          " Google로 로그인",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),

                  // Apple 로그인 버튼 (원래 코드 그대로 유지)
                  if (Platform.isIOS)
                    SizedBox(
                      height: 56,
                      child: SignInWithAppleButton(
                        onPressed: () async {
                          try {
                            await signInWithApple();
                          } catch (e) {
                            debugPrint("Apple login error: $e");
                          }
                        },
                        style: SignInWithAppleButtonStyle.white,
                        text: 'Apple로 로그인',
                      ),
                    ),

                  const SizedBox(height: 20),

                  Container(
                    width: double.infinity,
                    height: 1,
                    color: Colors.black12, // 구분선 색상 변경
                  ),

                  const Text(
                    "© 2025 XALUTE Health. All rights reserved.",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54, // 하단 텍스트 색상 변경
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 로딩 오버레이
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.4),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}