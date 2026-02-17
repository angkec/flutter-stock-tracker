# Stock Detail Linked Layout Adaptive Design (2026-02-17)

## 1. Goal

Fix and prevent the linked-mode chart compression issue in stock detail, while preparing for future growth from 2 subcharts (`MACD`, `ADX`) to 4-5 fixed subcharts.

The design goals are:

1. Keep linked mode mostly within one viewport (minimal extra scrolling).
2. Ensure both top and bottom panes remain readable.
3. Ensure main K-line and all fixed subcharts remain visible and readable.
4. Replace hardcoded chart-size formulas with an extensible layout allocation mechanism.
5. Provide configurable thresholds through a stock-detail debug entry, with safe defaults.

## 2. Confirmed Product Decisions

Based on discussion:

1. Preference profile: **Balanced** (`Option 2`) between readability and scrolling.
2. Configurability: **Code defaults + debug-editable overrides**.
3. Debug entry location: **Stock detail top-right menu**.
4. Scope of configuration: **Single global set** (not per-pane/per-indicator in this iteration).
5. Subcharts are currently fixed display; future user toggle customization is expected.

## 3. Root Cause Summary

Current linked mode uses a fixed container height in `StockDetailScreen` and fixed internal deductions in `LinkedDualKlineView`.

After adding ADX, each pane consumes additional fixed vertical budget, but the linked container height did not adapt proportionally. This allows the weekly main chart to collapse to very small height (~20 px in tests), causing unreadable display.

The issue is architectural, not only numeric:

1. Height logic is tied to current subchart count.
2. Any new subchart increases regression risk.
3. No centralized policy for minimum readability constraints.

## 4. Options Considered

### Option A: Continue Hardcoded Formula Tuning

Adjust constants (`containerHeight`, per-subchart heights) every time layout changes.

- Pros: minimal immediate code change.
- Cons: fragile; poor scalability for 4-5 subcharts; repeated regressions likely.

### Option B: Parameterize Existing Formula

Move constants to config, still using formula branches with explicit `MACD/ADX` assumptions.

- Pros: better than hardcoded values.
- Cons: still brittle when subchart count/types change.

### Option C: Declarative Budget + Generic Solver (Chosen)

Model pane constraints declaratively and resolve heights through a generic allocation solver.

- Pros: scalable with subchart growth; testable; future toggle mode ready.
- Cons: moderate one-time refactor.

Chosen: **Option C**.

## 5. Architecture

### 5.1 Configuration Model

Add `LinkedLayoutConfig` (global):

1. Main chart constraints: `mainMinHeight`, `mainIdealHeight`.
2. Subchart constraints: `subMinHeight`, `subIdealHeight`.
3. Shared layout constants: `infoBarHeight`, `subchartSpacing`, `paneGap`.
4. Pane split weights: `topPaneWeight`, `bottomPaneWeight`.
5. Container constraints: `containerMinHeight`, `containerMaxHeight`.
6. Version field for persistence migration.

Balanced defaults (confirmed baseline):

1. `mainMinHeight = 92`
2. `mainIdealHeight = 120`
3. `subMinHeight = 52`
4. `subIdealHeight = 78`

### 5.2 Config Service

Add `LinkedLayoutConfigService`:

1. Loads/saves debug overrides via `SharedPreferences`.
2. Exposes current config through `ChangeNotifier`.
3. Validates/clamps values and falls back to defaults on parse/migration failures.
4. Supports `resetToDefaults()`.

### 5.3 Layout Solver

Add `LinkedLayoutSolver` to compute pane and chart heights.

Inputs:

1. Screen/constrained available height.
2. Current `LinkedLayoutConfig`.
3. Pane descriptors with subchart count.

Outputs:

1. Linked container target height.
2. For each pane: main chart height.
3. For each pane: per-subchart resolved height list.

Solver policy:

1. Guarantee `mainMinHeight` first for both panes.
2. Guarantee each subchart `subMinHeight`.
3. Distribute remaining budget toward `ideal` heights.
4. If still insufficient, raise linked container height up to `containerMaxHeight`.
5. If constrained even beyond `containerMaxHeight`, keep min guarantees and allow page scrolling.

### 5.4 UI Integration

1. `StockDetailScreen` uses solver result for linked container height instead of hardcoded constant.
2. `LinkedDualKlineView` consumes resolved heights for top/bottom pane main chart and subcharts.
3. Top-right menu adds `联动布局调试` action opening a bottom sheet.
4. Bottom sheet edits global values (sliders/inputs), persists through `LinkedLayoutConfigService`.

## 6. Data Flow

### 6.1 Runtime Flow

1. Stock detail opens.
2. `LinkedLayoutConfigService` provides effective config (default + override).
3. `StockDetailScreen` computes linked container budget using solver.
4. `LinkedDualKlineView` receives resolved heights and renders panes/subcharts.
5. Any screen size change or subchart count change triggers solver recomputation.

### 6.2 Debug Config Flow

1. User opens stock detail menu -> `联动布局调试`.
2. User adjusts global thresholds.
3. Service validates and persists values.
4. Notifier updates listeners.
5. Linked layout recomputes and re-renders immediately.
6. `恢复默认` clears override and reapplies defaults.

## 7. Error Handling and Safety

1. Invalid persisted config -> fallback to defaults.
2. Missing fields or version mismatch -> migrate or fallback safely.
3. Any negative/invalid numeric value -> clamp to safe range.
4. Solver never returns non-positive heights.
5. If maximum allowed container still cannot satisfy ideals, solver preserves minima and degrades gracefully via scrolling.
6. Debug entry failures must never block stock detail rendering.

## 8. Testing Plan

### 8.1 Unit Tests

1. `LinkedLayoutSolver` with 2/3/5 subcharts.
2. Boundary conditions for small/large screen heights.
3. Correct min-first then ideal-fill behavior.
4. Proper clamp behavior with invalid config values.
5. `LinkedLayoutConfigService` load/save/reset/migration fallback.

### 8.2 Widget Tests

1. Linked mode weekly main chart remains above minimum threshold.
2. Both panes satisfy min main/subchart heights in balanced defaults.
3. Changing debug config triggers immediate relayout.
4. Increasing subchart count still produces readable layout.

### 8.3 Regression Tests

1. Preserve existing linked-mode crosshair sync behavior.
2. Preserve existing MACD/ADX rendering in linked mode.
3. Verify no chart collapse after adding additional fixed subcharts.

## 9. Implementation Sequence

1. Introduce `LinkedLayoutConfig` + defaults + validation.
2. Implement `LinkedLayoutConfigService` and persistence.
3. Implement `LinkedLayoutSolver` with unit tests.
4. Wire `StockDetailScreen` and `LinkedDualKlineView` to solver output.
5. Add stock-detail top-right debug bottom sheet.
6. Add/adjust widget regression tests for layout constraints.

## 10. Future Compatibility

When product switches from fixed subcharts to user-toggle mode, only the subchart list source changes.

No algorithmic rewrite should be required because solver input is already generic (`subchart count/spec list`), not hardcoded to `MACD/ADX`.

## 11. Non-Goals (This Iteration)

1. Full stock-detail page architecture rewrite (sliver/nested refactor).
2. Per-pane or per-indicator user-facing settings.
3. Public production settings UI for layout tuning.
4. Cross-device cloud sync of debug layout preferences.
