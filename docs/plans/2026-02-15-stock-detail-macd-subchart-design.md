# Stock Detail MACD SubChart Design

## Context

Current stock detail pages already render minute, daily, weekly, and linked daily-weekly K-line views. The app also has a local MACD cache pipeline (`MacdIndicatorService` + `MacdCacheStore`) and weekly prewarm in Data Management, but stock detail does not expose cached MACD values yet.

The product requirement is precise:
- Show MACD under daily and weekly K-line in stock detail.
- In linked mode, show both weekly MACD and daily MACD (one under each chart).
- MACD bars count must match currently visible K-line bars count.
- Display cached MACD only; if cache is missing, show an empty-state hint and do not compute on demand.
- Introduce a reusable class so future subcharts (RSI/KDJ/etc.) can be added without redesigning stock detail layout.

## Architecture

Introduce a composition widget: `KLineChartWithSubCharts`.

Responsibilities:
- Render the main `KLineChart`.
- Receive one or more subchart definitions and render them below the main chart.
- Maintain viewport synchronization between main chart and subcharts through a shared model.

Introduce a lightweight viewport model: `KLineViewport`.
- Fields: `startIndex`, `visibleCount`, `totalCount`, derived `endIndex`.
- Represents exactly which K-lines are visible in the main chart after zoom/scroll.

Extend `KLineChart` with a non-breaking callback:
- `onViewportChanged(ValueChanged<KLineViewport>)`
- Emits initial viewport and updates whenever zoom/scroll/data-length changes.

Subchart extension contract (code-level only):
- `KLineSubChart` abstract class / interface used by `KLineChartWithSubCharts`.
- First implementation: `MacdSubChart`.
- Future indicators only implement the same interface, without changing `StockDetailScreen` composition.

## Data Flow

For each daily/weekly/linked panel:
1. `StockDetailScreen` (or linked container) passes bars + stock identity + data type into `KLineChartWithSubCharts`.
2. `KLineChartWithSubCharts` receives viewport updates from inner `KLineChart`.
3. `MacdSubChart` obtains series from local cache (`MacdCacheStore.loadSeries`).
4. Subchart aligns cache points to bar dates and slices points by viewport range.
5. Subchart renders HIST bars + DIF/DEA lines only for the current viewport window.

No runtime compute path is triggered from stock detail.
If cache is missing/corrupted/unmatched:
- render stable placeholder text,
- keep primary K-line behavior unchanged.

Linked mode behavior:
- Weekly panel renders `KLineChartWithSubCharts` + weekly MACD.
- Daily panel renders `KLineChartWithSubCharts` + daily MACD.
- Existing crosshair link behavior remains unchanged in this iteration.

## UI and Interaction Rules

- Subchart container has fixed height to avoid scroll-jump when switching states.
- Main chart interactions (zoom, left/right scroll) drive MACD viewport updates in real time.
- MACD is visible only for daily/weekly/linked; minute mode unchanged.
- Missing cache message should be explicit and actionable (sync from Data Management).

## Error Handling

- Cache read failure (`JSON decode`, I/O) is treated as cache-miss for the UI.
- Date alignment produces overlap subset when partial match exists.
- If overlap is empty, show cache-miss placeholder.
- Errors should not block main chart rendering.
- Optional debug logs only under `kDebugMode`.

## Testing Strategy

1. `KLineChart` widget tests:
- emits initial viewport.
- emits updated viewport when user zooms (pinch) or scrolls.

2. `KLineChartWithSubCharts` tests:
- forwards viewport changes to subchart builders.
- renders no-subchart case same as baseline.

3. `MacdSubChart` tests:
- missing cache shows placeholder.
- viewport slicing count equals visible K-line count.
- daily/weekly cache separation is correct.

4. Integration tests (`stock_detail` + linked view):
- daily mode renders MACD panel.
- weekly mode renders MACD panel.
- linked mode renders two MACD panels (weekly + daily).

## YAGNI Boundaries

Not included in this iteration:
- Indicator plugin registry, dynamic runtime registration, or remote config.
- Drag-sort/hide/show management of multiple subcharts.
- Crosshair highlight synchronization inside subcharts.
- On-demand cache generation button.

The design intentionally delivers only required behavior with an extension seam for future indicators.
