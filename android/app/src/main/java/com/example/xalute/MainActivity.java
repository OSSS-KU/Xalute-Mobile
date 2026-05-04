package com.example.xalute;

import android.os.Bundle;
import android.util.Log;

import androidx.annotation.NonNull;

import com.google.android.gms.tasks.Task;
import com.google.android.gms.wearable.Asset;
import com.google.android.gms.wearable.DataClient;
import com.google.android.gms.wearable.DataEvent;
import com.google.android.gms.wearable.DataEventBuffer;
import com.google.android.gms.wearable.DataMapItem;
import com.google.android.gms.wearable.MessageClient;
import com.google.android.gms.wearable.MessageEvent;
import com.google.android.gms.wearable.Wearable;
import com.google.android.gms.wearable.PutDataRequest;
import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseUser;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.stream.Collectors;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity implements DataClient.OnDataChangedListener, MessageClient.OnMessageReceivedListener {
    private static final String CHANNEL = "com.example.xalute/watch";
    private static final String START_APP_PATH = "/start-app";
    private static final String GET_TOKEN_PATH = "/get-token";
    private static final String TOKEN_RESPONSE_PATH = "/token-response";
    private MethodChannel methodChannel;
    private MessageClient messageClient;
    private String nodeId;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        methodChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL);

        messageClient = Wearable.getMessageClient(this);
        getConnectedNode();

        methodChannel.setMethodCallHandler((call, result) -> {
            if (call.method.equals("isWatchConnected")) {
                result.success(nodeId != null);
            } else if (call.method.equals("launchWatchApp")) {
                if (nodeId == null) {
                    result.error("NO_NODE", "워치가 연결되지 않았습니다", null);
                    return;
                }

                try {
                    String token = call.argument("token");
                    String name = call.argument("name");
                    String birthDate = call.argument("birthDate");
                    String phoneNumber = call.argument("phoneNumber");
                    String address = call.argument("address");

                    JSONObject json = new JSONObject();
                    json.put("token", token != null ? token : "");
                    json.put("name", name != null ? name : "");
                    json.put("birthDate", birthDate != null ? birthDate : "");
                    json.put("phone", phoneNumber != null ? phoneNumber : "");
                    json.put("address", address != null ? address : "");
                    json.put("action", "launch_app");
                    String payload = json.toString();
                    Log.d("MainActivity", "📤 워치로 전송할 payload: " + payload);

                    messageClient.sendMessage(nodeId, START_APP_PATH, payload.getBytes())
                            .addOnSuccessListener(unused -> result.success(true))
                            .addOnFailureListener(e -> result.error("SEND_FAILED", "전송 실패", e));
                } catch (Exception e) {
                    result.error("JSON_ERROR", "JSON 생성 실패", e);
                }
            } else {
                result.notImplemented();
            }
        });
    }

    private void getConnectedNode() {
        Wearable.getNodeClient(this).getConnectedNodes()
                .addOnCompleteListener(task -> {
                    if (task.isSuccessful() && task.getResult() != null && !task.getResult().isEmpty()) {
                        nodeId = task.getResult().get(0).getId();
                    } else {
                        nodeId = null;
                    }
                });
    }

    @Override
    public void onMessageReceived(@NonNull MessageEvent messageEvent) {
        if (messageEvent.getPath().equals(GET_TOKEN_PATH)) {
            Log.d("MainActivity", "📩 워치로부터 Firebase 토큰 요청 수신");
            FirebaseUser user = FirebaseAuth.getInstance().getCurrentUser();
            if (user == null) {
                Log.e("MainActivity", "❌ 로그인된 사용자 없음");
                return;
            }
            user.getIdToken(true).addOnSuccessListener(result -> {
                String token = result.getToken();
                if (token == null) return;
                String sourceNodeId = messageEvent.getSourceNodeId();
                messageClient.sendMessage(sourceNodeId, TOKEN_RESPONSE_PATH, token.getBytes())
                        .addOnSuccessListener(unused -> Log.d("MainActivity", "✅ Firebase 토큰 워치로 전송 완료"))
                        .addOnFailureListener(e -> Log.e("MainActivity", "❌ 토큰 전송 실패", e));
            }).addOnFailureListener(e -> Log.e("MainActivity", "❌ 토큰 발급 실패", e));
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        Wearable.getDataClient(this).addListener(this);
        Wearable.getMessageClient(this).addListener(this);
    }

    @Override
    protected void onPause() {
        super.onPause();
        Wearable.getDataClient(this).removeListener(this);
        Wearable.getMessageClient(this).removeListener(this);
    }

    @Override
    public void onDataChanged(@NonNull DataEventBuffer dataEvents) {
        for (DataEvent event : dataEvents) {
            if (event.getType() == DataEvent.TYPE_CHANGED &&
                    event.getDataItem().getUri().getPath().equals("/ecg_file")) {

                DataMapItem dataMapItem = DataMapItem.fromDataItem(event.getDataItem());
                Asset asset = dataMapItem.getDataMap().getAsset("ecg_data");
                String result = dataMapItem.getDataMap().getString("result");
                long timestamp = dataMapItem.getDataMap().getLong("timestamp");
                String resultJson = dataMapItem.getDataMap().getString("result_json");
                String spo2Data = dataMapItem.getDataMap().getString("spo2_data");
                String heartRateData = dataMapItem.getDataMap().getString("heart_rate_data");
                String skinTempData = dataMapItem.getDataMap().getString("skin_temp_data");

                readAsset(asset, result, timestamp, resultJson, spo2Data, heartRateData, skinTempData);
            }
        }
    }

    private void readAsset(Asset asset, String result, long timestamp, String resultJson,
                            String spo2Data, String heartRateData, String skinTempData) {
        Wearable.getDataClient(this).getFdForAsset(asset).addOnSuccessListener(assetFd -> {
            try (InputStream inputStream = assetFd.getInputStream()) {
                if (inputStream != null) {
                    String content = new BufferedReader(new InputStreamReader(inputStream, StandardCharsets.UTF_8))
                            .lines().collect(Collectors.joining("\n"));

                    JSONObject data = new JSONObject();
                    data.put("fileContent", content);
                    data.put("result", result);
                    data.put("timestamp", timestamp);
                    data.put("result_json", resultJson);
                    data.put("spo2_data", spo2Data != null ? spo2Data : "[]");
                    data.put("heart_rate_data", heartRateData != null ? heartRateData : "[]");
                    data.put("skin_temp_data", skinTempData != null ? skinTempData : "[]");

                    methodChannel.invokeMethod("onEcgFileReceived", data.toString());
                    Log.d("MainActivity", "📥 Flutter로 ECG 파일, 결과, result_json, 바이탈 데이터 전달 완료");
                }
            } catch (Exception e) {
                Log.e("MainActivity", "❌ 파일 읽기 실패", e);
            }
        }).addOnFailureListener(e -> Log.e("MainActivity", "❌ Asset 가져오기 실패", e));
    }
}