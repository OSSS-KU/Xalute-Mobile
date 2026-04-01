import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'ecg_data_service.dart';
import 'package:flutter_date_pickers/flutter_date_pickers.dart' as dp;
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:xalute/screens/api_client.dart';
import 'package:kpostal/kpostal.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:xalute/screens/api_client.dart';

final api = ApiClient();


class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue) {
    String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    String formatted = '';
    if (digits.length <= 3) {
      formatted = digits;
    } else if (digits.length <= 7) {
      formatted = '${digits.substring(0, 3)}-${digits.substring(3)}';
    } else if (digits.length <= 11) {
      formatted =
      '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}';
    } else {
      // 11자리 초과하면 잘라 버림
      digits = digits.substring(0, 11);
      formatted =
      '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}



//name, birthDate, phone, address
class _SettingPageState extends State<SettingPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _birthdayController = TextEditingController();
  final TextEditingController _phoneNumberController  = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _detailedAddressController = TextEditingController();

  final FocusNode _nameFocus = FocusNode();
  DateTime? _selectedDate;
  File? _profileImage;
  bool _hasChanges = false;
  bool _showRoadAddressField = false;
  String postCode = '';
  String roadAddress = '';
  String jibunAddress = '';
  String detailedAddress = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _nameFocus.addListener(() {
      if (_nameFocus.hasFocus && _nameController.text.isEmpty) {
        _nameController.clear();
      }
    });
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('username') ?? '';
    final birthday = prefs.getString('birthDate') ?? '';
    final imagePath = prefs.getString('profileImagePath');
    final phoneNumber = prefs.getString('phoneNumber') ?? '';
    final address = prefs.getString('address') ?? '';
    final detail = prefs.getString('detailedAddress') ?? '';

    // Firebase User 정보
    final user = FirebaseAuth.instance.currentUser;
    String firebaseName = '';
    String firebaseEmail = '';
    if (user != null) {
      for (final providerProfile in user.providerData) {
        if (providerProfile.providerId == 'google.com') {
          firebaseName = providerProfile.displayName ?? '';
          firebaseEmail = providerProfile.email ?? '';
        }
      }
    }

    setState(() {
      _nameController.text =  name.isNotEmpty ? name : firebaseName;
      _birthdayController.text = birthday;
      _phoneNumberController.text = phoneNumber;
      _addressController.text = address;
      _detailedAddressController.text = detail;

      roadAddress = address;
      detailedAddress = detail;
      if (imagePath != null) {
        _profileImage = File(imagePath);
      }
    });

    final ecgService = Provider.of<EcgDataService>(context, listen: false);
    ecgService.setUserName(_nameController.text);
    ecgService.setBirthDate(_birthdayController.text);
    ecgService.setPhoneNumber(_phoneNumberController.text);
    ecgService.setAddress(_addressController.text);
    ecgService.setDetailedAddress(_detailedAddressController.text);
  }

  Future<void> _saveUserData() async {
    // 1. 로딩 시작 (화면 터치 방지)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFFB755B)),
      ),
    );

    try {
      // 2. 인증 정보 및 서비스 준비
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("로그인이 필요합니다.");
      final token = await user.getIdToken();
      final prefs = await SharedPreferences.getInstance();
      final ecgService = Provider.of<EcgDataService>(context, listen: false);

      // 3. 서버 전송용 데이터 구성 (보내주신 PATCH 명세 기준)
      final Map<String, dynamic> requestBody = {
        "uid": user.uid,
        "email": user.email,
        "name": _nameController.text,
        "phone": _phoneNumberController.text,
        "address": _addressController.text,
        "detail_address": _detailedAddressController.text,
        "userRole": "USER",
        "device": null,
        "onboarded": true, // 정보를 입력했으므로 true로 변경
      };

      // 4. 서버 API 호출 (PATCH /user)
      // URL은 본인의 서버 주소로 변경하세요 (예: http://10.0.2.2:3000/user)
      final url = Uri.parse('http://35.216.60.242:9101/user');
      final response = await http.patch(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );

      // 5. 로딩 다이얼로그 닫기
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      if (response.statusCode == 200) {
        // 6. 서버 저장 성공 시 -> 로컬 데이터 업데이트
        await prefs.setString('username', _nameController.text);
        await prefs.setString('birthDate', _birthdayController.text);
        await prefs.setString('phoneNumber', _phoneNumberController.text);
        await prefs.setString('address', _addressController.text);
        await prefs.setString('detailedAddress', _detailedAddressController.text);

        // Provider 업데이트 (메인 화면 등 즉시 반영)
        ecgService.setUserName(_nameController.text);
        ecgService.setBirthDate(_birthdayController.text);
        ecgService.setPhoneNumber(_phoneNumberController.text);
        ecgService.setAddress(_addressController.text);
        ecgService.setDetailedAddress(_detailedAddressController.text);

        // 프로필 이미지 경로 저장
        if (_profileImage != null) {
          await prefs.setString('profileImagePath', _profileImage!.path);
          ecgService.setProfileImagePath(_profileImage!.path);
        }

        setState(() => _hasChanges = false);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("서버와 기기에 정보가 저장되었습니다.")),
        );
      } else {
        throw Exception("서버 저장 실패 (상태코드: ${response.statusCode})");
      }
    } catch (e) {
      // 에러 시 로딩 다이얼로그 닫기
      if (mounted && Navigator.canPop(context)) Navigator.of(context, rootNavigator: true).pop();

      print("저장 에러: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("저장 중 오류가 발생했습니다: $e")),
      );
    }
  }

  Future<void> _logout() async {
    // SharedPreferences 초기화 (로컬 사용자 데이터 삭제)
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    // Firebase 로그아웃
    await FirebaseAuth.instance.signOut();

    // 상태 초기화 (UI 반영)
    if (!mounted) return;
    setState(() {
      _nameController.clear();
      _birthdayController.clear();
      _phoneNumberController.clear();
      _addressController.clear();
      _detailedAddressController.clear();
      _profileImage = null;
      _hasChanges = false;
      postCode = '';
      roadAddress = '';
      jibunAddress = '';
      detailedAddress = '';
    });

    // EcgDataService 초기화
    final ecgService = Provider.of<EcgDataService>(context, listen: false);
    ecgService.setUserName('');
    ecgService.setBirthDate('');
    ecgService.setPhoneNumber('');
    ecgService.setAddress('');
    ecgService.setProfileImagePath(null);

    // 로그인 화면으로 이동 (이전 스택 전체 제거)
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }


// 2. 날짜 선택 함수 구현
  Future<void> _selectBirthday() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000, 1, 1), // 초기 표시 날짜 (예: 2000년생)
      firstDate: DateTime(1900),          // 선택 가능한 가장 과거 날짜
      lastDate: DateTime.now(),           // 오늘 이후는 선택 불가
      locale: const Locale('ko', 'KR'),   // 한국어 설정 (main.dart 설정 필요)
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFFB755B), // 선택 바 및 버튼 색상
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        // intl 패키지를 사용하여 날짜 포맷팅
        _birthdayController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }
  Future<void> _pickImage() async {
    showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('프로필 사진 변경'),
          children: [
            SimpleDialogOption(
              child: const Text('카메라로 촬영'),
              onPressed: () async {
                Navigator.pop(context, true);
                final pickedFile = await ImagePicker().pickImage(source: ImageSource.camera);
                if (pickedFile != null) {
                  setState(() {
                    _profileImage = File(pickedFile.path);
                    _hasChanges = true;
                  });
                }
              },
            ),
            SimpleDialogOption(
              child: const Text('갤러리에서 선택'),
              onPressed: () async {
                Navigator.pop(context);
                final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
                if (pickedFile != null) {
                  setState(() {
                    _profileImage = File(pickedFile.path);
                    _hasChanges = true;
                  });
                }
              },
            ),
            SimpleDialogOption(
              child: const Text('기본 이미지로 변경'),
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _profileImage = null;
                  _hasChanges = true;
                });
              },
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _birthdayController.dispose();
    _phoneNumberController.dispose();
    _addressController.dispose();
    _detailedAddressController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFE),
      appBar: AppBar(
        title: const Text("Setting"),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.grey[100],
                    backgroundImage: _profileImage != null
                        ? FileImage(_profileImage!)
                        : const AssetImage('assets/icon/profile.png') as ImageProvider,
                  ),
                  const SizedBox(height: 8),
                  const Text('바꾸기', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text("이름", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              focusNode: _nameFocus,
              decoration: InputDecoration(
                hintText: "이름을 입력하세요",
                hintStyle: const TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                ),
                filled: true,
                fillColor: Colors.white,
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFEFEFEF)),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFEFEFEF)),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (_) => setState(() => _hasChanges = true),
            ),
            const SizedBox(height: 20),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text("전화번호", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phoneNumberController,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                PhoneNumberFormatter(),     // ← 자동 포맷 적용
              ],
              decoration: InputDecoration(
                hintText: "전화번호를 입력하세요",
                hintStyle: const TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                ),
                filled: true,
                fillColor: Colors.white,
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFEFEFEF)),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFEFEFEF)),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (_) => setState(() => _hasChanges = true),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => KpostalView(
                      useLocalServer: true,
                      localPort: 1024,
                      callback: (Kpostal result) {
                        setState(() {
                          postCode = result.postCode;
                          roadAddress = result.address;
                          jibunAddress = result.jibunAddress;

                          // 🔥 주소 검색 결과 → address controller
                          _addressController.text = roadAddress;
                          _hasChanges = true;
                        });
                      },
                    ),
                  ),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "도로명 주소",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFEFEFEF)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            roadAddress.isNotEmpty
                                ? roadAddress
                                : "도로명 주소를 검색하세요",
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.5,
                              color: roadAddress.isNotEmpty
                                  ? Colors.black
                                  : Colors.grey,
                            ),
                          ),
                        ),
                        const Icon(Icons.search, color: Colors.grey),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "상세주소",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _detailedAddressController,
                decoration: InputDecoration(
                  hintText: "상세주소를 입력하세요", // 🔥 처음에 보이는 회색 텍스트
                  hintStyle: const TextStyle(
                    color: Colors.grey,
                    fontSize: 16,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFFEFEFEF)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFFEFEFEF)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    detailedAddress = value;
                    _hasChanges = true;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text("생년월일", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _selectBirthday, // 탭하면 날짜 선택창 호출
              child: MouseRegion( // 웹/데스크톱 대응용 (선택 사항)
                cursor: SystemMouseCursors.click,
                child: AbsorbPointer( // 텍스트 필드를 직접 타이핑하는 것을 막고 클릭 이벤트만 전달
                  child: TextField(
                    controller: _birthdayController,
                    style: const TextStyle(fontSize: 15),
                    decoration: InputDecoration(
                      hintText: "날짜를 선택해 주세요",
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                      suffixIcon: const Icon(Icons.calendar_today, color: Color(0xFFFB755B)),
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0xFFEFEFEF)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0xFFFB755B)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _hasChanges ? _saveUserData : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("저장하기", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            // ↓ 여기서부터 추가된 부분
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('로그아웃'),
                      content: const Text('정말 로그아웃 하시겠습니까?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('취소', style: TextStyle(color: Colors.grey)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('로그아웃', style: TextStyle(color: Colors.redAccent)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) _logout();
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  '로그아웃',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent,
                  ),
                ),
              ),
            ),
// ↑ 여기까지 추가된 부분
          ],
        ),
      ),
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: TextEditingController(text: value),
          readOnly: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            enabledBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Color(0xFFEFEFEF)),
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Color(0xFFEFEFEF)),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildTextField(String label, TextEditingController controller, FocusNode? focusNode, {TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            enabledBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Color(0xFFEFEFEF)),
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Color(0xFFEFEFEF)),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onChanged: (value) => setState(() => _hasChanges = true),
        ),
      ],
    );
  }
}