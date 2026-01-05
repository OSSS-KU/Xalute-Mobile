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

  Future<UserCredential> signInWithApple() async {
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );

    final oauthCredential = OAuthProvider("apple.com").credential(
      idToken: appleCredential.identityToken,
      accessToken: appleCredential.authorizationCode,
    );

    return await _auth.signInWithCredential(oauthCredential);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF800020),
      body: Stack(
          children: [
            Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // XALUTE 로고 플레이

              const SizedBox(height: 180),
              const Text(
                "XALUTE",
                style: TextStyle(
                  fontSize: 60,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 20),

              const SizedBox(height: 60),
              // 로그인 제목


              if (!Platform.isIOS)
                const SizedBox(height: 56),


              // Google 로그인 버튼 (스타일 개선)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  // 세련된 버튼 스타일
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  minimumSize: const Size(double.infinity, 56), // 높이 증가
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10), // 둥근 모서리
                    side: const BorderSide(color: Color(0xFFE0E0E0), width: 1), // 옅은 테두리
                  ),
                  elevation: 0, // 그림자 추가
                ),
                onPressed:  _handleGoogleLogin,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    // 구글 아이콘을 추가
                    Image(
                      image: NetworkImage(
                          'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/512px-Google_%22G%22_logo.svg.png'),
                      height: 24.0, // 아이콘 크기
                      width: 24.0,
                    ),
                    Text(
                      " Google로 로그인",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Apple 로그인 버튼 (높이 맞춤)
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
                  // 배경색이 어두우므로 흰색 스타일이 더 잘 어울립니다.
                  style: SignInWithAppleButtonStyle.white,
                  text: 'Apple로 로그인',
                ),
              ),

              // 애플 버튼 아래에 시각적 음영(구분선) 추가
              const SizedBox(height: 30), // 구분선 위 간격
              Container(
                width: double.infinity,
                height: 1,
                color: Colors.white38, // 옅은 흰색으로 구분선 표현
              ),
              const SizedBox(height: 30), // 구분선 아래 간격

              // 하단에 버전 정보나 저작권 정보를 위한 텍스트 추가
              const Text(
                "© 2025 XALUTE Health. All rights reserved.",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white54,
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
      ), // ← 여기가 Stack 닫는 괄호
    );
  }
}