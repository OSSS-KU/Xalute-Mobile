# 점수 계산 방식 문서

일일 리포트에 표시되는 점수들의 weight와 계산식 정리.
(UI에서는 이 설명을 제거했으며, 실제 산정 로직은 본 문서를 기준으로 한다.)

관련 코드:
- 건강점수 / 위험도: `lib/screens/vital_signs_service.dart`
- 에너지 / 수면 점수: `lib/screens/samsung_health_service.dart`, `android/app/src/main/kotlin/com/example/xalute/MainActivity.kt`

---

## 1. 건강점수 (Wellness Score)

자체 측정값(SpO2 / 심박수 / 피부온도)을 baseline과 비교해 0~100으로 산출.

### 가중치 (weight)
| 항목 | weight | 정규화 후 |
|------|--------|-----------|
| 심박수 (HR) | 0.25 | 50% |
| 산소포화도 (SpO2) | 0.15 | 30% |
| 피부온도 (SkinTemp) | 0.10 | 20% |
| 호흡수 (RR) | — | 미측정(제외) |
| HRV | — | 미측정(제외) |

> 호흡수·HRV는 현재 센서로 수집 불가 → 제외하고 남은 항목의 weight 합으로 정규화한다.
> (측정 가능한 항목만 합산 후 `score = Σ(devScore·weight) / Σ(weight)`)

### 항목별 점수 (devScore)
```
devScore(value, baseline) = clamp(100 - |value - mean| / std * 25, 0, 100)
```
- baseline에서 1σ 벗어날 때마다 25점 감점. (mean에 가까울수록 100점)

### 단기(24h) vs 장기(28일)
- **단기**: 최근 측정 세션 평균값 vs 28일 baseline
- **장기**: 28일 누적 평균값 vs 인구 표준(population norm)

### baseline
- 윈도우: 28일. 항목별 표본 **3개 이상**이어야 개인 baseline 사용, 미만이면 인구 표준 사용.
- 개인화 적용 조건(`usingPersonalBaseline`): 최근 **7일 내 측정 5회 이상**.
- 인구 표준값:
  | 항목 | mean | std |
  |------|------|-----|
  | HR | 70 | 12 |
  | SpO2 | 97.5 | 1.2 |
  | SkinTemp | 33.0 | 1.2 |

---

## 2. 건강 위험도 (개선 NEWS2)

항목별 0~3점을 합산. `item = max(σ기반 점수, 절대 임계 점수)`.

### σ 기반 점수
`s = |value - mean| / std` → `s≤1:0, s≤2:1, s≤3:2, 그 외:3`

### 절대 임계(floor)
| 항목 | 3점 | 2점 | 1점 | 0점 |
|------|-----|-----|-----|-----|
| SpO2 | ≤91 | ≤93 | ≤95 | 그 외 |
| HR | ≤40 또는 ≥131 | ≤50 또는 ≥111 | ≥91 | 그 외 |
| SkinTemp | ≤30 또는 ≥39 | ≤31 또는 ≥38 | ≤32 또는 ≥37 | 그 외 |

### 조치(action)
- 총점 ≥ 4 **또는** 단일 항목 3점 → **즉시 경고** (immediateAlert)
- 총점 ≥ 1 → **경과 관찰** (observe24h)
- 그 외 → **정상** (recordOnly)

---

## 3. 에너지 점수 (Samsung Health)

헤드라인 점수는 **Samsung Health SDK가 산출한 완성값**을 그대로 읽어온다
(`DataType.EnergyScoreType.ENERGY_SCORE`, 전날~오늘 중 최신 1건). 내부 알고리즘은 비공개.

### 서브 항목
| 항목 | 산출 | 비고 |
|------|------|------|
| 활동 | 전날 칼로리/활동시간 기반(삼성 내부) | SDK 서브점수 미제공 |
| 수면 | 삼성 수면 점수 입력 | 아래 4) 참고 |
| 수면 중 HR | 수면 세션 구간 평균 심박수 | 낮을수록 회복 양호 |
| 수면 중 HRV | 자율신경 회복 지표 | **SDK 1.1.0 미노출** |

---

## 4. 수면 점수 (Samsung Health)

헤드라인 점수는 **Samsung SDK `SLEEP_SCORE`** 값을 그대로 사용. 서브컴포넌트는 단계별 시간으로 자체 계산.

### 서브컴포넌트 점수식
| 컴포넌트 | 계산 |
|----------|------|
| 총 수면 시간 | 7–9h=100 / 6–7h·9–10h=80 / 5–6h·10–11h=60 / 그 외=30 |
| 수면 주기 | REM 진입 횟수: 5회=100 / 4=85 / 3=70 / 2=50 / 1=30 / 0=0 |
| 깨거나 뒤척임 | AWAKE/총수면: <5%=100 / <10%=80 / <20%=60 / 그 외=30 |
| 신체 회복 | `clamp((deep%/20)*100, 0, 100)` — 딥슬립 20%가 만점 |
| 정신 회복 | `clamp((rem%/25)*100, 0, 100)` — REM 25%가 만점 |

### 단계 시간 정의
- `totalSleep = deep + rem + light` (AWAKE 제외)
- `total = SDK duration ?? (totalSleep + awake)`
- `cycleCount` = 수면 세션 내 REM 단계 진입 횟수
- 단계 데이터 출처: Samsung 수면 세션(`SleepSession.stages`: DEEP/REM/LIGHT/AWAKE)
