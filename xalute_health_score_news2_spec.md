# Xalute — 건강점수(Wellness Score) & 개선 NEWS2 도입 스펙

> Two-tier monitoring 구조에 들어갈 **건강점수(Wellness Score)** 와 **개선 NEWS2(Improved NEWS2)** 의 설계 및 구현 사양.
> 본 문서는 Claude Code에서 곧바로 모듈/스키마/알고리즘 구현을 시작할 수 있도록 작성되었다.

---

## 0. TL;DR

- **목적:** 워치 디바이스에서 수집한 활력징후를 기반으로 (1) 평소의 건강 상태 baseline 을 만들고(건강점수), (2) ECG 측정 등 trigger 시점에 임상적 악화 위험을 판단(개선 NEWS2)하는 **two-tier monitoring** 시스템을 구축한다.
- **Tier 1 — 건강점수(Wellness Score):** 워치에서 **상시 수집**되는 데이터로 단기(24h) / 장기(7d, 28d) 점수를 산출하여 **개인화 baseline** 으로 누적한다.
- **Tier 2 — 개선 NEWS2:** ECG 또는 spot-check 시점에 측정값을 **장기 baseline과의 상대평가**로 점수화하여 즉시 경고/관찰 판단에 사용한다.
- **타깃 디바이스:** Samsung Galaxy Watch (Galaxy / Samsung Sensor SDK) 우선, Apple Watch (HealthKit) 호환 고려.
- **비고:** 가중치, 임계치, 점수 환산식의 구체 수치는 본 문서의 **예시값**이며, 실측 데이터 확보 후 calibration 단계에서 튜닝한다.

---

## 1. 시스템 구조 (Two-tier Monitoring)

```
┌──────────────────────────────────────────────────────────────────┐
│  워치 센서 (PPG / 가속도계 / 피부온도 / SpO2)                     │
│        │                                                         │
│        ▼                                                         │
│  [Tier 1] 건강점수 Wellness Score                                │
│   - 상시 수집 → 단기(24h) / 장기(7d, 28d) 점수                    │
│   - 출력: 점수 + 항목별 baseline (mean, std, percentile)          │
│        │                                                         │
│        ▼ (baseline 제공)                                          │
│  [Tier 2] 개선 NEWS2                                             │
│   - ECG/Spot-check trigger 시점 측정                              │
│   - 측정값 vs 장기 baseline → 상대평가 점수                       │
│   - 1~3점: 경과 관찰 (24h)  /  4점 이상: 즉시 경고                │
└──────────────────────────────────────────────────────────────────┘
```

**핵심 원칙**

1. 건강점수는 **연속적**, 개선 NEWS2는 **이벤트 기반**.
2. 개선 NEWS2의 모든 비교 기준선은 건강점수 모듈이 만든 장기 baseline 을 사용 → **두 모듈은 baseline schema 를 공유**한다.
3. 점수 산정 알고리즘은 외부에서 **가중치/임계치를 주입 가능**하도록 한다 (calibration 용이성).

---

## 2. 데이터 수집 — 활용 가능한 센서 매핑

### 2.1 디바이스별 데이터 가용성

| Metric | Samsung (Galaxy Sensor SDK) | Apple (HealthKit) |
|---|---|---|
| Activity | 가속도계 기반 추정 | ✅ 직접 제공 |
| 혈중 산소 (SpO2) | PPG 기반 추정 | ✅ |
| 심박수 (HR) | ✅ 직접 제공 | ✅ |
| HRV | PPG 기반 추정 (편차 큼) | ✅ |
| 안정 호흡수 (Resting RR) | PPG + 가속도계 | ✅ |
| 호흡수 (RR) | PPG | ✅ |
| 수면 양/질 | 가속도계 | ✅ |
| 수면 구조 (REM/NREM) | 가속도계 | ✅ |
| 피부 온도 | ✅ 직접 제공 (Skin temp, ≠ core temp) | ✅ |

### 2.2 Samsung SDK 추출 키 (참조)

| Metric | ValueKey | 비고 |
|---|---|---|
| SpO2 | `ValueKey.SpO2Set` | NEWS2 Scale 1 점수에 직접 사용 가능 |
| HR | `ValueKey.HeartRateSet` | NEWS2 0~3점 매핑에 직접 사용 가능 |
| 피부 온도 | `ValueKey.SkinTemperatureSet` | core temp 대비 보정 필요 |
| 호흡수 | `ValueKey.AccelerometerSet` / `ValueKey.PpgGreenSet` | 직접 제공 X → 신호처리 필요 (가속도계 흉벽 움직임 또는 PPG respiratory modulation) |

### 2.3 신호처리/추정 정책

- **HRV:** PPG 기반 추정은 편차가 크므로 **rMSSD** 로 계산 (Garmin·WHOOP 기준과 동일). 측정 구간은 수면 중 slow-wave sleep 기간에 가중치를 두는 방식을 우선 검토.
- **안정 호흡수:** Garmin 방식(24h 중 가장 낮은 30분 평균) 또는 WHOOP 방식(slow-wave sleep 가중치) 중 선택. 초기 구현은 Garmin 방식이 단순하여 우선.
- **호흡수:** Samsung SDK는 직접 제공하지 않으므로 별도 신호처리 모듈 필요. 참고문헌 [Kazemi et al., 2023] 의 CNN 기반 추정 방식 적용 가능.
- **수면:** SDK 문서에 공식이 비공개 → 가속도계 기반 **자체 알고리즘** 필요 (수면/각성, 수면 구조 추정).
- **피부 온도:** core temp 보정 계수 도입. NEWS2 적용 시에는 **상대 변화량(Δtemp)** 위주로 평가.

---

## 3. Tier 1 — 건강점수(Wellness Score)

기존 워치 시장 분석 결과(Samsung Energy / Garmin Body·Training / WHOOP Recovery·Strain·Stress / Apple Watch)에 기반하여 **단기 + 장기** 2개 점수를 산출한다.

### 3.1 단기 건강점수 (24h)

- **목적:** 최근 24시간 컨디션 측정.
- **점수 범위:** 0~100.
- **방식:** 각 항목의 **개인 baseline 대비 편차**를 0~100 점수로 환산 후 가중합.

| 항목 | 가중치 (예시) |
|---|---|
| 호흡수 편차 | 30% |
| HRV 편차 | 25% |
| 안정 호흡수 편차 | 15% |
| 산소포화도 편차 | 15% |
| 피부 온도 편차 | 10% |
| 수면 편차 (vs 28일 평균) | 5% |

> 가중치는 NEWS2 우선순위 가이드(영국 보건당국)에 따른 **호흡수·의식·혈압 우선** 원칙을 반영하여 설정. 의식·혈압이 워치에서 측정 불가하므로 호흡 관련 비중을 높임.

### 3.2 장기 건강점수 (7d / 28d)

- **목적:** 개인화 baseline 누적 및 장기 추세 모니터링. **Tier 2 NEWS2의 비교 기준선**으로 사용.
- **점수 범위:** 0~100.
- **참조 윈도우:** 7일 점수 + 28일 평균/percentile.

| 항목 | 가중치 (예시) |
|---|---|
| 28일 평균 안정 호흡수 | 25% |
| 28일 평균 HRV (percentile) | 25% |
| Sleep duration & regularity | 20% |
| 28일 평균 산소포화도 | 15% |
| 활동량 | 10% |
| 28일 RR baseline 안정성 | 5% |

### 3.3 알고리즘 의사코드

```python
def wellness_score_short(metrics_24h, baseline_28d, weights):
    """단기 건강점수 (0~100)"""
    deviations = {
        k: deviation_to_score(metrics_24h[k], baseline_28d[k])  # 0~100
        for k in weights.keys()
    }
    return sum(deviations[k] * w for k, w in weights.items())

def wellness_score_long(metrics_28d, population_norms, weights):
    """장기 건강점수 (0~100)"""
    components = {
        "rr_resting":  to_score(metrics_28d.rr_resting_mean,  population_norms.rr_resting),
        "hrv":         percentile_score(metrics_28d.hrv_mean, population_norms.hrv),
        "sleep":       sleep_score(metrics_28d.sleep_duration, metrics_28d.sleep_regularity),
        "spo2":        to_score(metrics_28d.spo2_mean, population_norms.spo2),
        "activity":    activity_score(metrics_28d.activity),
        "rr_stability":stability_score(metrics_28d.rr_28d_series),
    }
    return sum(components[k] * w for k, w in weights.items())
```

### 3.4 Baseline 산출 규칙

- **누적 윈도우:** 7일(short baseline), 28일(long baseline).
- **저장 통계량:** mean, std, percentile (p10, p25, p50, p75, p90).
- **부족 데이터 처리:** 최소 7일 데이터 누적 전에는 baseline 으로 사용하지 않고 population norm 으로 fallback.
- **이상치 처리:** 운동·발열·음주 등의 명백한 outlier 는 baseline 산출에서 제외 (rule-based + IQR filter).

---

## 4. Tier 2 — 개선 NEWS2 (Improved NEWS2)

### 4.1 표준 NEWS2 개요

영국 표준 조기경고체계. 7가지 활력징후를 점수화하여 환자 악화 위험을 평가한다.

**총점에 따른 모니터링 가이드 (표준 NEWS2)**

| 총점 | 모니터링 주기 | 대응 |
|---|---|---|
| 0점 | 12시간마다 | 기본 모니터링 |
| 1~4점 | 4~6시간마다 | 간호사 평가 |
| 단일 항목 3점 | 1시간마다 | 의료팀 보고 |
| 5점 이상 (긴급) | 1시간마다 | 60분 내 평가, 모니터링 환경 이동 고려 |
| 7점 이상 (응급) | 지속 모니터링 | 30분 내 평가, ICU/HDU 전실 고려 |

**표준 NEWS2 7가지 활력징후**

| # | 항목 | 워치 측정 가능 여부 |
|---|---|---|
| 1 | 호흡수 (Respiration rate) | △ (신호처리 필요) |
| 2 | 산소포화도 (SpO2) | ✅ (Scale 1) |
| 3 | 산소 투여 여부 (Air or O2) | ❌ (사용자 입력 필요, 일반 사용자는 N/A) |
| 4 | 수축기 혈압 (SBP) | ❌ (워치 직접 측정 불가) |
| 5 | 심박수 (Pulse) | ✅ |
| 6 | 의식수준/혼동 (ACVPU) | ❌ |
| 7 | 체온 (Temperature) | △ (skin temp → core temp 보정 필요) |

### 4.2 개선 NEWS2 — 핵심 변경점

표준 NEWS2는 **임상 절대값 기준**(예: HR ≥ 131 → 3점)이지만, 워치 사용자는 일반인 + 만성 컨디션 차이가 크다. 따라서 본 시스템은 **개인 baseline 대비 상대평가**로 변환한다.

> **핵심 정의:**
> - 개선 NEWS2는 장기 건강점수에서 산출된 **호흡수 / 산소포화도 / 심박수 / 체온 평균값**을 baseline 으로 사용.
> - 측정값이 baseline 대비 얼마나 벗어났는지로 0~3점 매핑.
> - 워치 측정 불가 항목(산소 투여·혈압·의식)은 항목 자체를 제외하거나 사용자 입력 옵션으로 둔다.

### 4.3 점수 매핑 (예시)

각 항목을 **표준편차(σ) 기반**으로 점수화:

| 편차 구간 | 점수 |
|---|---|
| baseline ± 1σ | 0 |
| baseline ± 1~2σ | 1 |
| baseline ± 2~3σ | 2 |
| baseline ± 3σ 초과 | 3 |

**임상적 절대 한계치(absolute floor/ceiling)** 는 별도로 적용 (예: SpO2 < 92% 는 baseline 무관하게 최소 2점). 이 부분은 표준 NEWS2 기준을 참고하여 구성한다.

### 4.4 알림 정책

| 총점 | 동작 |
|---|---|
| 0점 | 결과만 기록 |
| 1~3점 | **경과 관찰** — 24시간 후 재측정. 동일 점수 지속 시 사용자 경고 |
| 4점 이상 | **즉시 경고** — 사용자 알림 + 측정 권장 |

> 표준 NEWS2의 5점/7점 임계와는 다르게, 워치 사용 환경(비임상·일반인)을 고려하여 임계를 4점으로 낮췄다. calibration 단계에서 false-positive rate 와 함께 재조정한다.

### 4.5 알고리즘 의사코드

```python
def improved_news2(measurement, baseline_long, absolute_rules):
    """
    measurement: 현재 측정값 dict (rr, spo2, hr, temp, ...)
    baseline_long: 28일 baseline (mean, std)
    absolute_rules: 임상 절대 한계치 (e.g., spo2 < 92 -> at least 2)
    """
    item_scores = {}
    for key, value in measurement.items():
        if key not in baseline_long:
            continue
        # 1) 개인 baseline 기반 σ 점수
        sigma_score = sigma_to_news_score(value, baseline_long[key].mean,
                                                  baseline_long[key].std)
        # 2) 임상 절대 한계치와 비교 → 둘 중 큰 값
        abs_score = absolute_rules.evaluate(key, value)
        item_scores[key] = max(sigma_score, abs_score)

    total = sum(item_scores.values())
    has_single_3 = any(s == 3 for s in item_scores.values())

    return NEWS2Result(
        total=total,
        items=item_scores,
        single_item_3=has_single_3,
        action=decide_action(total, has_single_3),
    )

def decide_action(total, single_3):
    if total >= 4 or single_3:
        return "IMMEDIATE_ALERT"
    if 1 <= total <= 3:
        return "OBSERVE_24H"
    return "RECORD_ONLY"
```

---

## 5. 구현 요구사항

### 5.1 모듈 구조 (제안)

```
xalute_health/
├── ingest/                     # 센서 데이터 수집/정제
│   ├── samsung_sdk.py
│   ├── healthkit.py
│   └── signal_processing/      # 호흡수, HRV, 수면 추정
│       ├── respiration.py
│       ├── hrv.py
│       └── sleep.py
├── baseline/                   # 누적 baseline 산출
│   ├── window.py               # 7d / 28d 윈도우 관리
│   ├── stats.py                # mean, std, percentile
│   └── outlier.py              # IQR / rule-based 제외
├── wellness_score/             # Tier 1
│   ├── short_term.py           # 24h 점수
│   ├── long_term.py            # 7d / 28d 점수
│   └── weights.py              # 가중치 주입 인터페이스
├── news2/                      # Tier 2
│   ├── scoring.py              # σ 기반 + 절대 한계치
│   ├── alert_policy.py         # 1~3 / 4+ 분기
│   └── absolute_rules.py       # 표준 NEWS2 절대 임계
├── models/                     # 데이터 클래스/스키마
│   ├── measurement.py
│   ├── baseline.py
│   └── score.py
└── tests/
    ├── fixtures/               # 가상 사용자 시계열
    ├── test_wellness_score.py
    └── test_news2.py
```

### 5.2 데이터 모델 (요지)

```python
@dataclass
class VitalMeasurement:
    timestamp: datetime
    rr: float | None              # 호흡수 (breaths/min)
    rr_resting: float | None      # 안정 호흡수
    spo2: float | None            # 산소포화도 (%)
    hr: float | None              # 심박수 (bpm)
    hrv_rmssd: float | None       # HRV (ms)
    skin_temp: float | None       # 피부 온도 (℃)
    activity_level: float | None  # 활동량 지표

@dataclass
class BaselineStats:
    mean: float
    std: float
    p10: float; p25: float; p50: float; p75: float; p90: float
    n_samples: int
    window_days: int              # 7 or 28

@dataclass
class NEWS2Result:
    total: int
    items: dict[str, int]
    single_item_3: bool
    action: Literal["RECORD_ONLY", "OBSERVE_24H", "IMMEDIATE_ALERT"]
    measured_at: datetime
```

### 5.3 외부 인터페이스

- **Score 조회 API:** `GET /score/wellness/short`, `GET /score/wellness/long`
- **NEWS2 trigger:** `POST /news2/evaluate` — body: 측정값. response: `NEWS2Result`.
- **Baseline 조회:** `GET /baseline?window=28d` — 디버깅 / 사용자 인사이트 노출용.
- **가중치 설정:** config 파일(YAML/JSON) 또는 admin API 로 calibration 가능하게.

### 5.4 보정/캘리브레이션 단계

1. **Phase 1 (구현 검증):** 합성 시계열 + 공개 데이터셋으로 score 분포 정상성 확인.
2. **Phase 2 (개인화):** 실사용자 7~28일 누적 후 baseline 안정성 확인.
3. **Phase 3 (튜닝):** 가중치/임계치 조정. 특히 개선 NEWS2의 4점 임계는 false positive rate 와 trade-off 검토.

### 5.5 테스트 케이스 필수 항목

- 데이터 누적 7일 미만: population fallback 동작.
- 명백한 outlier(운동 직후 HR 급등): baseline 제외 확인.
- 호흡수 신호처리 결과의 missing rate 가 높을 때 점수 안정성.
- 단일 항목 3점 발생 시 alert 분기.
- baseline 변화 시 NEWS2 점수의 monotonic 한 변화 (역전 없음).

---

## 6. 결정 필요 사항 (TODO before implementation)

- [ ] **호흡수 추정 알고리즘 채택** — 자체 구현 vs Kazemi et al. (2023) 모델 도입
- [ ] **수면 추정 알고리즘 채택** — Samsung SDK 비공개로 인한 자체 구현 범위
- [ ] **피부 온도 → core temp 보정 계수** — 실측 캘리브레이션 데이터 필요
- [ ] **개선 NEWS2의 absolute floor 정확한 임계치** — 임상 자문 필요
- [ ] **단기/장기 가중치 최종 결정** — 본 문서는 예시값만 제시
- [ ] **혈압·의식 항목 처리 방안** — 제외할지, 사용자 입력 옵션을 둘지

---

## 7. References

1. Wilson, A. J., Parker, A. J., Kitchen, G. B., Martin, A., Hughes-Noehrer, L., Nirmalan, M., ... & Thistlethwaite, F. C. (2025). The completeness, accuracy and impact on alerts, of wearable vital signs monitoring in hospitalised patients. *BMC Digital Health*, 3(1), 13.
2. Bignami, E. G., Fornaciari, A., Fedele, S., Madeo, M., Panizzi, M., Marconi, F., ... & Bellini, V. (2025). Wearable Devices in Healthcare Beyond the One-Size-Fits All Paradigm. *Sensors*, 25(20), 6472.
3. Kazemi, K., Azimi, I., Liljeberg, P., & Rahmani, A. M. (2023). Robust CNN-based respiration rate estimation for smartwatch PPG and IMU. In *Proc. 10th Intl. Conf. on Bioinformatics Research and Applications*, 94–100.
4. Ghiasi, S., Zhu, T., Lu, P., Hagenah, J., Khanh, P. N. Q., Hao, N. V., ... & Clifton, D. A. (2022). Sepsis mortality prediction using wearable monitoring in low–middle income countries. *Sensors*, 22(10), 3866.
5. Royal College of General Practitioners. (2022). NEWS2 score for assessing the patient at risk of deterioration. RCGP.
6. Doherty, C., Baldwin, M., Lambe, R., Burke, D., & Altini, M. (2025). Readiness, recovery, and strain: an evaluation of composite health scores in consumer wearables. *Translational Exercise Biomedicine*, 2(2), 128–144.
7. Riccalton, V., Threlfall, L., Ananthakrishnan, A., Cong, C., Milne-Ives, M., Le Roux, P., ... & Meinert, E. (2025). Modifications to the National Early Warning Score 2: a scoping review. *BMC Medicine*, 23(1), 154.
