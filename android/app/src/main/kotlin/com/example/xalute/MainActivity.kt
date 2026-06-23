package com.example.xalute

import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.Asset
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.Node
import com.google.android.gms.wearable.Wearable
import com.samsung.android.sdk.health.data.HealthDataService
import com.samsung.android.sdk.health.data.HealthDataStore
import com.samsung.android.sdk.health.data.data.HealthDataPoint
import com.samsung.android.sdk.health.data.permission.AccessType
import com.samsung.android.sdk.health.data.permission.Permission
import com.samsung.android.sdk.health.data.request.DataType
import com.samsung.android.sdk.health.data.request.DataTypes
import com.samsung.android.sdk.health.data.request.InstantTimeFilter
import com.samsung.android.sdk.health.data.request.LocalDateFilter
import com.samsung.android.sdk.health.data.request.Ordering
import com.samsung.android.sdk.health.data.request.ReadDataRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.nio.charset.StandardCharsets
import java.time.Instant
import java.time.LocalDate

class MainActivity : FlutterActivity(), DataClient.OnDataChangedListener {

    private val TAG = "MainActivity"
    private val WATCH_CHANNEL = "com.example.xalute/watch"
    private val ECG_CHANNEL = "com.example.health/ecg"
    private val HEALTH_CHANNEL = "com.example.health/vitals"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var healthStore: HealthDataStore? = null
    private var watchChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initSamsungHealth()

        val watchChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WATCH_CHANNEL)
        this.watchChannel = watchChannel
        watchChannel
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isWatchConnected" -> isWatchConnected(result)
                    "launchWatchApp" -> {
                        val name = call.argument<String>("name") ?: ""
                        val birthDate = call.argument<String>("birthDate") ?: ""
                        val token = call.argument<String>("token") ?: ""
                        launchWatchApp(name, birthDate, token, result)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ECG_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getECGData" -> result.success(emptyList<Any>())
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HEALTH_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getLatestVitals" -> {
                        val hours = call.argument<Int>("hours") ?: 24
                        getLatestVitals(hours, result)
                    }
                    "getSamsungHealthSummary" -> getSamsungHealthSummary(result)
                    else -> result.notImplemented()
                }
            }
    }

    // ── Samsung Health 초기화 ─────────────────────────────────────────

    private fun initSamsungHealth() {
        scope.launch {
            try {
                val store = HealthDataService.getStore(applicationContext)
                healthStore = store
                requestHealthPermissions(store)
            } catch (e: Exception) {
                Log.w(TAG, "Samsung Health 연결 실패: ${e.message}")
            }
        }
    }

    private suspend fun requestHealthPermissions(store: HealthDataStore) {
        val permissions = setOf(
            Permission.of(DataTypes.HEART_RATE, AccessType.READ),
            Permission.of(DataTypes.BLOOD_OXYGEN, AccessType.READ),
            Permission.of(DataTypes.SKIN_TEMPERATURE, AccessType.READ),
            Permission.of(DataTypes.SLEEP, AccessType.READ),
            Permission.of(DataTypes.ENERGY_SCORE, AccessType.READ),
        )
        try {
            store.requestPermissions(permissions, this@MainActivity)
            Log.d(TAG, "Samsung Health 권한 획득 완료")
        } catch (e: Exception) {
            Log.w(TAG, "Samsung Health 권한 요청 실패: ${e.message}")
        }
    }

    // ── Samsung Health 종합 요약 ──────────────────────────────────────

    private fun getSamsungHealthSummary(result: MethodChannel.Result) {
        scope.launch {
            try {
                val store = healthStore
                if (store == null) {
                    result.error("NOT_CONNECTED", "Samsung Health 미연결", null)
                    return@launch
                }
                val energyScore = readEnergyScore(store)
                val sleepMap = readSleepData(store)

                // 수면 시간대 HR 읽기 (sessionStart/End 사용)
                val sleepHR = run {
                    val start = sleepMap["sessionStartMs"] as? Long
                    val end = sleepMap["sessionEndMs"] as? Long
                    if (start != null && end != null && end > start)
                        readSleepHR(store, Instant.ofEpochMilli(start), Instant.ofEpochMilli(end))
                    else null
                }

                result.success(mapOf(
                    "energyScore" to energyScore,
                    "sleepScore" to sleepMap["sleepScore"],
                    "totalSleepMinutes" to sleepMap["totalSleepMinutes"],
                    "deepSleepMinutes" to sleepMap["deepSleepMinutes"],
                    "remSleepMinutes" to sleepMap["remSleepMinutes"],
                    "lightSleepMinutes" to sleepMap["lightSleepMinutes"],
                    "awakeDuringMinutes" to sleepMap["awakeDuringMinutes"],
                    "sleepCycleCount" to sleepMap["sleepCycleCount"],
                    "physicalRecoveryScore" to sleepMap["physicalRecoveryScore"],
                    "mentalRecoveryScore" to sleepMap["mentalRecoveryScore"],
                    "sleepHR" to sleepHR,
                ))
            } catch (e: Exception) {
                Log.e(TAG, "건강 요약 조회 실패: ${e.message}")
                result.error("ERROR", e.message, null)
            }
        }
    }

    private suspend fun readEnergyScore(store: HealthDataStore): Double? {
        return try {
            val dateFilter = LocalDateFilter.of(LocalDate.now().minusDays(1), LocalDate.now())
            @Suppress("UNCHECKED_CAST")
            val builder = DataTypes.ENERGY_SCORE.readDataRequestBuilder
                    as ReadDataRequest.LocalDateBuilder<HealthDataPoint>
            val request = builder
                .setLocalDateFilter(dateFilter)
                .setOrdering(Ordering.DESC)
                .setLimit(1)
                .build()
            val response = withContext(Dispatchers.IO) { store.readDataAsync(request).get() }
            response.dataList.firstOrNull()
                ?.getValue(DataType.EnergyScoreType.ENERGY_SCORE)
                ?.toDouble()
        } catch (e: Exception) {
            Log.w(TAG, "에너지 점수 조회 실패: ${e.message}")
            null
        }
    }

    private suspend fun readSleepData(store: HealthDataStore): Map<String, Any?> {
        return try {
            val endTime = Instant.now()
            val startTime = endTime.minusSeconds(36 * 3600) // 최근 36시간
            val timeFilter = InstantTimeFilter.of(startTime, endTime)

            @Suppress("UNCHECKED_CAST")
            val builder = DataTypes.SLEEP.readDataRequestBuilder
                    as ReadDataRequest.DualTimeBuilder<HealthDataPoint>
            val request = builder
                .setInstantTimeFilter(timeFilter)
                .setOrdering(Ordering.DESC)
                .setLimit(1)
                .build()
            val response = withContext(Dispatchers.IO) { store.readDataAsync(request).get() }
            val dp = response.dataList.firstOrNull() ?: return emptyMap()

            val sleepScore = dp.getValue(DataType.SleepType.SLEEP_SCORE)
            val durationJava = dp.getValue(DataType.SleepType.DURATION)
            val sessions = dp.getValue(DataType.SleepType.SESSIONS)

            var deepMs = 0L; var remMs = 0L; var lightMs = 0L; var awakeMs = 0L
            var cycleCount = 0; var prevWasRem = false

            sessions?.forEach { session ->
                session.stages?.forEach { stage ->
                    val ms = stage.endTime.toEpochMilli() - stage.startTime.toEpochMilli()
                    when (stage.stage) {
                        DataType.SleepType.StageType.DEEP  -> { deepMs += ms; prevWasRem = false }
                        DataType.SleepType.StageType.REM   -> {
                            remMs += ms
                            if (!prevWasRem) cycleCount++
                            prevWasRem = true
                        }
                        DataType.SleepType.StageType.LIGHT -> { lightMs += ms; prevWasRem = false }
                        DataType.SleepType.StageType.AWAKE -> { awakeMs += ms; prevWasRem = false }
                        else -> {}
                    }
                }
            }

            val totalSleepMs = deepMs + remMs + lightMs
            val totalMs = durationJava?.toMillis() ?: (totalSleepMs + awakeMs)

            // 신체 회복: 딥슬립 20%가 만점 기준
            val physicalScore = if (totalSleepMs > 0)
                ((deepMs.toDouble() / totalSleepMs * 100.0) / 20.0 * 100.0).coerceIn(0.0, 100.0).toInt()
            else null

            // 정신 회복: REM 25%가 만점 기준
            val mentalScore = if (totalSleepMs > 0)
                ((remMs.toDouble() / totalSleepMs * 100.0) / 25.0 * 100.0).coerceIn(0.0, 100.0).toInt()
            else null

            mapOf(
                "sleepScore"            to sleepScore,
                "totalSleepMinutes"     to (totalMs / 60000L).toInt(),
                "deepSleepMinutes"      to (deepMs / 60000L).toInt(),
                "remSleepMinutes"       to (remMs / 60000L).toInt(),
                "lightSleepMinutes"     to (lightMs / 60000L).toInt(),
                "awakeDuringMinutes"    to (awakeMs / 60000L).toInt(),
                "sleepCycleCount"       to cycleCount,
                "physicalRecoveryScore" to physicalScore,
                "mentalRecoveryScore"   to mentalScore,
                "sessionStartMs"        to dp.startTime?.toEpochMilli(),
                "sessionEndMs"          to dp.endTime?.toEpochMilli(),
            )
        } catch (e: Exception) {
            Log.w(TAG, "수면 데이터 조회 실패: ${e.message}")
            emptyMap()
        }
    }

    private suspend fun readSleepHR(store: HealthDataStore, start: Instant, end: Instant): Double? {
        return try {
            @Suppress("UNCHECKED_CAST")
            val builder = DataTypes.HEART_RATE.readDataRequestBuilder
                    as ReadDataRequest.DualTimeBuilder<HealthDataPoint>
            val request = builder
                .setInstantTimeFilter(InstantTimeFilter.of(start, end))
                .setOrdering(Ordering.ASC)
                .build()
            val response = withContext(Dispatchers.IO) { store.readDataAsync(request).get() }
            val hrs = response.dataList.mapNotNull {
                it.getValue(DataType.HeartRateType.HEART_RATE)?.toDouble()
            }
            if (hrs.isEmpty()) null else hrs.average()
        } catch (e: Exception) {
            Log.w(TAG, "수면 중 HR 조회 실패: ${e.message}")
            null
        }
    }

    // ── 바이탈 (HR / SpO2 / SkinTemp) ────────────────────────────────

    private fun getLatestVitals(hours: Int, result: MethodChannel.Result) {
        scope.launch {
            try {
                val store = healthStore ?: run {
                    result.error("NOT_CONNECTED", "Samsung Health 미연결", null)
                    return@launch
                }
                val endTime = Instant.now()
                val startTime = endTime.minusSeconds(hours.toLong() * 3600)
                val timeFilter = InstantTimeFilter.of(startTime, endTime)

                val hrList = mutableListOf<Map<String, Any>>()
                val spo2List = mutableListOf<Map<String, Any>>()
                val tempList = mutableListOf<Map<String, Any>>()

                runCatching {
                    @Suppress("UNCHECKED_CAST")
                    val req = (DataTypes.HEART_RATE.readDataRequestBuilder as ReadDataRequest.DualTimeBuilder<HealthDataPoint>)
                        .setInstantTimeFilter(timeFilter).setOrdering(Ordering.DESC).setLimit(100).build()
                    withContext(Dispatchers.IO) { store.readDataAsync(req).get() }
                        .dataList.forEach { dp ->
                            val hr = dp.getValue(DataType.HeartRateType.HEART_RATE) ?: return@forEach
                            hrList.add(mapOf(
                                "heartRate" to hr.toDouble(),
                                "min" to (dp.getValue(DataType.HeartRateType.MIN_HEART_RATE) ?: hr).toDouble(),
                                "max" to (dp.getValue(DataType.HeartRateType.MAX_HEART_RATE) ?: hr).toDouble(),
                                "startTime" to dp.startTime.toEpochMilli(),
                            ))
                        }
                }.onFailure { Log.w(TAG, "HR 조회 실패: ${it.message}") }

                runCatching {
                    @Suppress("UNCHECKED_CAST")
                    val req = (DataTypes.BLOOD_OXYGEN.readDataRequestBuilder as ReadDataRequest.DualTimeBuilder<HealthDataPoint>)
                        .setInstantTimeFilter(timeFilter).setOrdering(Ordering.DESC).setLimit(100).build()
                    withContext(Dispatchers.IO) { store.readDataAsync(req).get() }
                        .dataList.forEach { dp ->
                            val spo2 = dp.getValue(DataType.BloodOxygenType.OXYGEN_SATURATION) ?: return@forEach
                            spo2List.add(mapOf(
                                "oxygenSaturation" to spo2.toDouble(),
                                "min" to (dp.getValue(DataType.BloodOxygenType.MIN_OXYGEN_SATURATION) ?: spo2).toDouble(),
                                "max" to (dp.getValue(DataType.BloodOxygenType.MAX_OXYGEN_SATURATION) ?: spo2).toDouble(),
                                "startTime" to dp.startTime.toEpochMilli(),
                            ))
                        }
                }.onFailure { Log.w(TAG, "SpO2 조회 실패: ${it.message}") }

                runCatching {
                    @Suppress("UNCHECKED_CAST")
                    val req = (DataTypes.SKIN_TEMPERATURE.readDataRequestBuilder as ReadDataRequest.DualTimeBuilder<HealthDataPoint>)
                        .setInstantTimeFilter(timeFilter).setOrdering(Ordering.DESC).setLimit(100).build()
                    withContext(Dispatchers.IO) { store.readDataAsync(req).get() }
                        .dataList.forEach { dp ->
                            val temp = dp.getValue(DataType.SkinTemperatureType.SKIN_TEMPERATURE) ?: return@forEach
                            tempList.add(mapOf(
                                "skinTemperature" to temp.toDouble(),
                                "min" to (dp.getValue(DataType.SkinTemperatureType.MIN_SKIN_TEMPERATURE) ?: temp).toDouble(),
                                "max" to (dp.getValue(DataType.SkinTemperatureType.MAX_SKIN_TEMPERATURE) ?: temp).toDouble(),
                                "startTime" to dp.startTime.toEpochMilli(),
                            ))
                        }
                }.onFailure { Log.w(TAG, "피부온도 조회 실패: ${it.message}") }

                result.success(mapOf(
                    "heartRate" to hrList,
                    "bloodOxygen" to spo2List,
                    "skinTemperature" to tempList,
                ))
            } catch (e: Exception) {
                result.error("READ_ERROR", e.message, null)
            }
        }
    }

    // ── 워치 채널 ─────────────────────────────────────────────────────

    private fun isWatchConnected(result: MethodChannel.Result) {
        scope.launch {
            try {
                val nodes = withContext(Dispatchers.IO) {
                    Tasks.await(Wearable.getNodeClient(applicationContext).connectedNodes)
                }
                result.success(nodes.isNotEmpty())
            } catch (e: Exception) {
                Log.w(TAG, "워치 연결 확인 실패: ${e.message}")
                result.success(false)
            }
        }
    }

    private fun launchWatchApp(name: String, birthDate: String, token: String, result: MethodChannel.Result) {
        scope.launch {
            try {
                val nodes: List<Node> = withContext(Dispatchers.IO) {
                    Tasks.await(Wearable.getNodeClient(applicationContext).connectedNodes)
                }
                if (nodes.isEmpty()) { result.error("NO_WATCH", "연결된 워치 없음", null); return@launch }
                val payload = "$name|$birthDate|$token".toByteArray(Charsets.UTF_8)
                val mc: MessageClient = Wearable.getMessageClient(applicationContext)
                nodes.forEach { node ->
                    withContext(Dispatchers.IO) { Tasks.await(mc.sendMessage(node.id, "/launch-ecg", payload)) }
                }
                result.success(null)
            } catch (e: Exception) {
                result.error("LAUNCH_ERROR", e.message, null)
            }
        }
    }

    // ── 워치 ECG 수신 (Wearable Data Layer) ───────────────────────────

    override fun onResume() {
        super.onResume()
        Wearable.getDataClient(this).addListener(this)
    }

    override fun onPause() {
        super.onPause()
        Wearable.getDataClient(this).removeListener(this)
    }

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        for (event in dataEvents) {
            if (event.type == DataEvent.TYPE_CHANGED &&
                event.dataItem.uri.path == "/ecg_file") {
                val dataMap = DataMapItem.fromDataItem(event.dataItem).dataMap
                val asset = dataMap.getAsset("ecg_data") ?: continue
                readAsset(
                    asset,
                    dataMap.getString("result"),
                    dataMap.getLong("timestamp"),
                    dataMap.getString("result_json"),
                    dataMap.getString("spo2_data"),
                    dataMap.getString("heart_rate_data"),
                    dataMap.getString("skin_temp_data"),
                )
            }
        }
    }

    private fun readAsset(
        asset: Asset,
        result: String?,
        timestamp: Long,
        resultJson: String?,
        spo2Data: String?,
        heartRateData: String?,
        skinTempData: String?,
    ) {
        Wearable.getDataClient(this).getFdForAsset(asset)
            .addOnSuccessListener { assetFd ->
                try {
                    assetFd.inputStream.use { input ->
                        val content = BufferedReader(
                            InputStreamReader(input, StandardCharsets.UTF_8)
                        ).readText()

                        val data = JSONObject().apply {
                            put("fileContent", content)
                            put("result", result)
                            put("timestamp", timestamp)
                            put("result_json", resultJson)
                            put("spo2_data", spo2Data ?: "[]")
                            put("heart_rate_data", heartRateData ?: "[]")
                            put("skin_temp_data", skinTempData ?: "[]")
                        }

                        watchChannel?.invokeMethod("onEcgFileReceived", data.toString())
                        Log.d(TAG, "📥 Flutter로 ECG 파일/바이탈 전달 완료")
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "❌ 파일 읽기 실패: ${e.message}")
                }
            }
            .addOnFailureListener { e -> Log.e(TAG, "❌ Asset 가져오기 실패: ${e.message}") }
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.coroutineContext[kotlinx.coroutines.Job]?.cancel()
    }
}
