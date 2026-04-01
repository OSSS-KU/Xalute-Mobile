
  import 'dart:io' show Platform;
  import 'dart:convert';
  import 'dart:developer' as dev;
  import 'package:flutter/material.dart';
  import 'package:http/http.dart' as http;
  import 'package:firebase_auth/firebase_auth.dart';
  import 'package:google_sign_in/google_sign_in.dart';
  import 'package:sign_in_with_apple/sign_in_with_apple.dart';
  import 'package:flutter_dotenv/flutter_dotenv.dart';
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

    // 서버 정보를 가져오고 라우팅하는 핵심 함수
    Future<void> _fetchAndNavigate(String token) async {
      try {
        // 본인의 서버 Base URL로 수정하세요 (예: http://10.0.2.2:3000)
        final url = Uri.parse('http://35.216.60.242:9101/user/self');

        final response = await http.get(
          url,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );

        // 이 줄을 추가해서 서버가 뭐라고 답변하는지 확인하세요!
        print("서버 응답 상태코드: ${response.statusCode}");
        print("서버 응답 내용: ${response.body}");

        if (response.statusCode == 200) {
          final Map<String, dynamic> responseData = json.decode(response.body);
          final userData = responseData['data'];
          final bool isOnboarded = userData['onboarded'] ?? false;

          // 3. 서버 데이터를 로컬 서비스 및 저장소에 동기화
          await _syncUserData(userData);

          if (mounted) {
            if (true) {
              // 온보딩 완료 시 -> 메인 페이지
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const MainTabPage()),
              );
            } else {
              // 온보딩 미완료 시 -> 설문 페이지
              Navigator.pushReplacementNamed(context, '/survey');
            }
          }
        } else {
          throw Exception("서버에서 유저 정보를 가져오는데 실패했습니다.");
        }
      } catch (e) {
        rethrow;
      }
    }


    Future<void> _syncUserData(Map<String, dynamic> data) async {
      final prefs = await SharedPreferences.getInstance();
      final ecgService = Provider.of<EcgDataService>(context, listen: false);

      // 이름 저장 및 서비스 업데이트
      String name = data['name'] ?? 'Unknown';
      await prefs.setString('username', name);
      ecgService.setUserName(name);

      // 나머지 정보들도 동기화 (값이 있을 경우에만)
      if (data['address'] != null) {
        await prefs.setString('address', data['address']);
        ecgService.setAddress(data['address']);
        print("✅ address loaded: ${data['address']}");
      }

      if (data['phone'] != null) {
        await prefs.setString('phoneNumber', data['phone']);
        ecgService.setPhoneNumber(data['phone']);
        print("✅ phone loaded: ${data['phone']}");
      }

      if (data['detail_address'] != null) {
        // 주의: 로컬 키(detailedAddress)와 서버 키(detail_address) 매칭 확인 완료
        await prefs.setString('detailedAddress', data['detail_address']);
        ecgService.setDetailedAddress(data['detail_address']);
        print("✅ detailed address loaded: ${data['detail_address']}");
      }

      // 온보딩 상태도 로컬에 백업
      await prefs.setBool('isSurveyCompleted', data['onboarded'] ?? false);

      // --- 동기화 결과 통합 로그 ---
      print("""
      🚀 [UserData Sync 완료]
      - Name: ${ecgService.userName}
      - Phone: ${ecgService.phoneNumber}
      - Address: ${ecgService.address}
      - Detail: ${ecgService.detailedAddress}
      - Onboarded: ${data['onboarded']}
      -------------------------
      """);
    }
    Future<void> _handleGoogleLogin() async {
      setState(() {
        _isLoading = true;
      });

      final prefs = await SharedPreferences.getInstance();
      bool isSurveyCompleted = prefs.getBool('isSurveyCompleted') ?? false;

      try {
        // 1. 구글/파이어베이스 로그인 및 ID 토큰 획득
        final String? idToken = await signInAndGetIdToken();

        if (idToken != null && mounted) {
          // 2. 서버에서 내 정보 가져오기 (GET /user/self)
          await _fetchAndNavigate(idToken);
        } else {
          debugPrint("Error: Firebase ID Token 획득 실패.");
        }
      } catch (e) {
        debugPrint("Google login error: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("로그인 중 오류가 발생했습니다: $e")),
        );
      } finally {
        if (mounted) setState(() => _isLoading = false);
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

      // 1. Firebase에 로그인을 먼저 수행
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      final User? user = userCredential.user;

      if (user != null) {
        // 🔥 [핵심 수정 부분]
        // googleAuth.idToken(구글 토큰) 대신
        // user.getIdToken()(파이어베이스 토큰)을 새로 발급받아서 리턴해야 합니다.
        final String? firebaseIdToken = await user.getIdToken(true); // true는 강제 갱신

        // 유저 정보 처리 (기존 로직)
        String firebaseName = user.displayName ?? '';
        onLoginComplete(firebaseName);

        return firebaseIdToken; // 서버가 기대하는 "aud": "xalute-firebase" 토큰
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

    void onLoginComplete(String name) {
      final ecgService = Provider.of<EcgDataService>(context, listen: false);

      ecgService.setUserName(
        name
      );
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
                        children: [
                          Image.asset(
                            'assets/icon/google_logo.png',
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