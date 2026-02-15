# stock_rtwatcher

`stock_rtwatcher` is a Flutter-based market monitoring app focused on A-share workflows:

- watchlist and full-market monitoring
- minute/daily/weekly K-line data management
- strategy helpers (pullback, breakout, backtest)
- industry-level buildup radar with score/rank trends

## Getting Started

```bash
flutter pub get
flutter run
```

## App Architecture Overview

The app is wired in `lib/main.dart` using `Provider` / `ChangeNotifierProvider` / `ProxyProvider`.
Core services are created once at startup and injected into screens and feature services.

### Layers

1. **Presentation layer (`lib/screens`, `lib/widgets`)**
   - Tabbed app shell (`watchlist`, `market`, `industry`, `breakout`)
   - Feature UIs render service state and trigger actions

2. **Application/service layer (`lib/services`)**
   - Business workflows such as market refresh, strategy computation, and industry radar recalculation
   - Notable services: `IndustryBuildUpService`, `IndustryScoreEngine`, `BacktestService`, `PullbackService`

3. **Data/repository layer (`lib/data`)**
   - `DataRepository` is the single data access contract
   - `MarketDataRepository` coordinates local storage + remote fetch + freshness checks

4. **Infrastructure layer (`lib/data/storage`, network clients)**
   - SQLite metadata/state (`MarketDatabase`, `IndustryBuildUpStorage`, `DateCheckStorage`)
   - Compressed K-line files on disk (`KLineFileStorage`)
   - TDX connectivity (`TdxClient`, `TdxPool`)

### Key Runtime Flows

- **Market data flow**: UI → `MarketDataRepository` → local cache / TDX fetch → repository streams update consumers.
- **Industry radar flow**: UI/service trigger → `IndustryBuildUpService.recalculate()` → feature extraction + scoring + ranking → `IndustryBuildUpStorage` → UI trend boards.

## Industry Scoring Design (建仓雷达)

Industry scoring is a two-stage pipeline:

1) **Feature generation & quality scoring** in `IndustryBuildUpService`
2) **Composite score smoothing + ranking** in `IndustryScoreEngine`

### 1) Minute-bar feature extraction (stock/day)

For each stock/day, minute bars are aggregated into:

- directional pressure: `xHat = Σ(v_i * tanh(r_i / τ)) / (Σv_i + ε)`
- where `r_i = ln(close_i / close_{i-1})`, `τ = 0.001`
- coverage and validity gates use:
  - expected minutes: `240`
  - min daily turnover: `2e7`
  - min minute coverage: `0.9`
  - max single-minute volume share: `0.12`

Only “passed” stock/day features are used for standard aggregation.

### 2) Industry vs market aggregation

For each trading day:

- market baseline `xM` = mean `xHat` across passed stocks
- industry signal `xI` = weighted sum of member `xHat`
- weights are amount-based with cap `0.08`, then re-normalized
- concentration metric uses HHI from the final weights
- relative signal: `xRel = xI - xM`
- breadth: positive-member ratio within passed industry members

### 3) Relative strength normalization (`Z_rel`)

Per industry, `xRel` is converted to rolling z-score using a 20-day window:

- `μ` and `σ` from windowed `xRel`
- `Z_rel = (xRel - μ) / (σ + ε)`

### 4) Quality factor (`Q`)

`Q` is the clipped product of four components:

- `Q_coverage = min(1, passedCount / 8)`
- `Q_breadth = clip01((breadth - 0.30) / (0.55 - 0.30))`
- `Q_conc = exp(-12 * max(0, HHI - 0.06))`
- `Q_persist` from recent `Z_rel` persistence (`lookback=5`, threshold `Z>1.0`, need `>=3`, else `0.6`)

Final: `Q = clip01(Q_coverage * Q_breadth * Q_conc * Q_persist)`

### 5) Composite score and ranking

`IndustryScoreEngine` computes:

- `zPos = max(Z_rel, 0)`
- breadth gate mapped from breadth using config (`b0=0.25`, `b1=0.50`, gate range `[0.5, 1.0]`)
- raw score: `rawScore = ln(1 + zPos) * Q * breadthGate`
- smoothed trend score: `scoreEma_t = α * rawScore_t + (1 - α) * scoreEma_{t-1}`, default `α=0.30`

Daily ranking is by `scoreEma` descending (with deterministic tie-break by industry name). The engine also stores `rank_change` and direction arrow (`↑`, `↓`, `→`).

### 6) Persistence schema

Industry radar records are persisted in SQLite table `industry_buildup_daily` with core fields:

- `z_rel`, `z_pos`, `breadth`, `breadth_gate`, `q`
- `raw_score`, `score_ema`
- `rank`, `rank_change`, `rank_arrow`
- `x_i`, `x_m`, member/passed counts, timestamps

## Testing Notes

- This project supports parallel test execution (for example: `flutter test -j 8`).
- Test database isolation is configured in `test/flutter_test_config.dart`.
- The test bootstrap assigns a per-process temporary SQLite directory, which prevents cross-worker DB lock/contention issues.
