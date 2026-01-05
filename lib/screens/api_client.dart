import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:xalute/main.dart';
import 'package:firebase_auth/firebase_auth.dart';

const String baseUrl = 'http://34.44.245.53:3000/';

// ======================
// ApiClient
// ======================
class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  String? _idToken;
  final _client = http.Client();

  void setupTokenListener() {
    FirebaseAuth.instance.idTokenChanges().listen((user) async {
      if (user != null) {
        _idToken = await user.getIdToken();  // 최신 토큰 업데이트
      } else {
        _idToken = null;
      }
    });
  }


  Future<http.Response> _executeRequest(String path, String method, {dynamic body}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("Not logged in");

    // 항상 최신 ID Token
    final token = await user.getIdToken(); // Lazy refresh 포함

    final uri = Uri.parse('$baseUrl$path');
    final headers = {
      "Authorization": "Bearer $token",
      "Content-Type": "application/json",
    };

    switch (method) {
      case 'POST':
        return await _client.post(uri, headers: headers, body: body);
      case 'GET':
        return await _client.get(uri, headers: headers);
      case 'PUT':
        return await _client.put(uri, headers: headers, body: body);
      case 'DELETE':
        return await _client.delete(uri, headers: headers);
      default:
        throw Exception("Unsupported HTTP method: $method");
    }
  }

  // wrapper 함수
  Future<http.Response> post(String path, {dynamic body}) async {
    return await _executeRequest(path, 'POST', body: body);
  }

  Future<http.Response> get(String path) async {
    return await _executeRequest(path, 'GET');
  }

  Future<http.Response> put(String path) async {
    return await _executeRequest(path, 'PUT');
  }
}