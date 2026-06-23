package com.example.xalute

import android.util.Log
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import com.google.firebase.auth.FirebaseAuth
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext

class TokenListenerService : WearableListenerService() {

    private val TAG = "TokenListenerService"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != "/get-token") return
        scope.launch {
            try {
                val user = FirebaseAuth.getInstance().currentUser
                val token = user?.getIdToken(true)?.await()?.token // true = 강제 갱신 (만료 토큰 방지)
                if (token == null) {
                    Log.w(TAG, "Firebase 토큰 없음 (로그인 필요)")
                    return@launch
                }
                withContext(Dispatchers.IO) {
                    Wearable.getMessageClient(applicationContext)
                        .sendMessage(event.sourceNodeId, "/token-response", token.toByteArray(Charsets.UTF_8))
                        .await()
                }
                Log.d(TAG, "워치에 토큰 전송 완료")
            } catch (e: Exception) {
                Log.e(TAG, "토큰 전송 실패: ${e.message}")
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.coroutineContext[kotlinx.coroutines.Job]?.cancel()
    }
}
