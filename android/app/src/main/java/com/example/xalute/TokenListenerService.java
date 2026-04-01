package com.example.xalute;

import android.util.Log;

import androidx.annotation.NonNull;

import com.google.android.gms.wearable.MessageEvent;
import com.google.android.gms.wearable.Wearable;
import com.google.android.gms.wearable.WearableListenerService;
import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseUser;

public class TokenListenerService extends WearableListenerService {
    private static final String TAG = "TokenListenerService";
    private static final String GET_TOKEN_PATH = "/get-token";
    private static final String TOKEN_RESPONSE_PATH = "/token-response";

    @Override
    public void onMessageReceived(@NonNull MessageEvent messageEvent) {
        if (!messageEvent.getPath().equals(GET_TOKEN_PATH)) return;

        Log.d(TAG, "📩 [Service] 워치로부터 Firebase 토큰 요청 수신");

        FirebaseUser user = FirebaseAuth.getInstance().getCurrentUser();
        if (user == null) {
            Log.e(TAG, "❌ 로그인된 사용자 없음");
            return;
        }

        String sourceNodeId = messageEvent.getSourceNodeId();

        user.getIdToken(true)
                .addOnSuccessListener(result -> {
                    String token = result.getToken();
                    if (token == null) return;
                    Wearable.getMessageClient(this)
                            .sendMessage(sourceNodeId, TOKEN_RESPONSE_PATH, token.getBytes())
                            .addOnSuccessListener(unused -> Log.d(TAG, "✅ Firebase 토큰 워치로 전송 완료"))
                            .addOnFailureListener(e -> Log.e(TAG, "❌ 토큰 전송 실패", e));
                })
                .addOnFailureListener(e -> Log.e(TAG, "❌ 토큰 발급 실패", e));
    }
}
