# Industry Detail SW Daily K + EMA13 Breadth Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Show SW level-1 industry index daily K-line (260 trading-day window) as the main chart in industry detail, with EMA13 breadth as the sub chart in the same top section.

**Architecture:** Add a dedicated SW industry mapping pipeline (`industry name -> l1_code`) sourced from Tushare `index_member_all` (doc_id=335), cache it locally, and resolve mapping in `IndustryDetailScreen` before loading SW daily bars through `SwIndexRepository`. Reuse existing `KLineChart` for the main chart and keep `IndustryEmaBreadthChart` as the EMA13 breadth sub chart.

**Tech Stack:** Flutter, Provider, existing `TushareClient`, `SwIndexRepository`, file-based cache stores in `lib/data/storage`, widget tests with `flutter_test`.

---

### Task 1: Add SW level-1 mapping API contract in Tushare client

**Files:**
- Modify: `lib/services/tushare_client.dart`
- Create: `lib/models/sw_industry_l1_member.dart`
- Test: `test/services/tushare_client_test.dart`

**Step 1: Write failing tests for `index_member_all` parsing and request envelope**

Add tests in `test/services/tushare_client_test.dart`:

```dart
test('fetchSwIndustryMembers sends index_member_all request', () async {
  late Map<String, dynamic> captured;
  final client = TushareClient(
    token: 't',
    postJson: (payload) async {
      captured = payload;
      return {
        'code': 0,
        'msg': '',
        'data': {
          'fields': ['l1_code', 'l1_name', 'ts_code', 'name', 'is_new'],
          'items': [
            ['801010.SI', '农林牧渔', '000001.SZ', '平安银行', 'Y'],
          ],
        },
      };
    },
  );

  await client.fetchSwIndustryMembers();

  expect(captured['api_name'], 'index_member_all');
  expect((captured['params'] as Map)['is_new'], 'Y');
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/services/tushare_client_test.dart`

Expected: FAIL with missing `fetchSwIndustryMembers` or missing model parse support.

**Step 3: Implement model and client method**

Create `lib/models/sw_industry_l1_member.dart` with:
- `SwIndustryL1Member` class
- fields at least: `l1Code`, `l1Name`, `tsCode`, `stockName`, `isNew`
- `fromTushareMap(Map<String, dynamic>)`

Add to `lib/services/tushare_client.dart`:
- `Future<List<SwIndustryL1Member>> fetchSwIndustryMembers({String isNew = 'Y'})`
- request `api_name: 'index_member_all'`, params includes `is_new`
- parser similar to `parseSwDailyResponse`
- throw `TushareApiException` when `code != 0`

**Step 4: Run tests to verify green**

Run: `flutter test test/services/tushare_client_test.dart`

Expected: PASS.

**Step 5: Checkpoint**

Record changed files and keep branch uncommitted unless user explicitly requests commit.

---

### Task 2: Add local mapping store and resolver service (`industry -> l1_code`)

**Files:**
- Create: `lib/data/storage/sw_industry_l1_mapping_store.dart`
- Create: `lib/services/sw_industry_index_mapping_service.dart`
- Create: `lib/models/sw_industry_index_mapping.dart`
- Test: `test/data/storage/sw_industry_l1_mapping_store_test.dart`
- Test: `test/services/sw_industry_index_mapping_service_test.dart`

**Step 1: Write failing storage tests**

In `test/data/storage/sw_industry_l1_mapping_store_test.dart`, cover:
- save/load mapping map
- returns empty when no file
- overwrite existing data atomically

**Step 2: Run storage tests and verify fail**

Run: `flutter test test/data/storage/sw_industry_l1_mapping_store_test.dart`

Expected: FAIL because store does not exist.

**Step 3: Implement storage**

Implement `SwIndustryL1MappingStore` consistent with existing file stores (`MarketSnapshotStore`, `IndustryEmaBreadthCacheStore`):
- use `KLineFileStorage` + `AtomicFileWriter`
- persist JSON map `{industryName: l1Code}`
- expose `saveAll(Map<String, String>)`, `loadAll()`, `clear()`

**Step 4: Write failing service tests**

In `test/services/sw_industry_index_mapping_service_test.dart`, cover:
- refresh from Tushare members dedupes by `l1_code + l1_name`
- `resolveTsCodeByIndustry('半导体')` returns mapped code
- fallback to cached mapping when refresh is not called
- ignores empty/null-like names

**Step 5: Run service tests and verify fail**

Run: `flutter test test/services/sw_industry_index_mapping_service_test.dart`

Expected: FAIL because service/model not implemented.

**Step 6: Implement model + service**

`SwIndustryIndexMapping` model:
- `industryName`, `l1Code`, optional `updatedAt`

`SwIndustryIndexMappingService`:
- ctor deps: `TushareClient`, `SwIndustryL1MappingStore`
- `Future<Map<String, String>> refreshFromTushare({String isNew = 'Y'})`
- `Future<String?> resolveTsCodeByIndustry(String industry)`
- ensure level-1 mapping via `l1_name -> l1_code`

**Step 7: Run tests to verify green**

Run:
- `flutter test test/data/storage/sw_industry_l1_mapping_store_test.dart`
- `flutter test test/services/sw_industry_index_mapping_service_test.dart`

Expected: PASS.

**Step 8: Checkpoint**

Record changed files and keep branch uncommitted unless user explicitly requests commit.

---

### Task 3: Wire mapping service and refresh entrypoint in app DI + Data Management

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/screens/data_management_screen.dart`
- Test: `test/screens/data_management_screen_test.dart`

**Step 1: Write failing UI test for mapping refresh action availability**

In `test/screens/data_management_screen_test.dart`, add assertion:
- when token is configured, a control/button exists for SW industry mapping refresh
- when no token, action leads to token dialog path (or disabled state)

**Step 2: Run targeted test and verify fail**

Run: `flutter test test/screens/data_management_screen_test.dart`

Expected: FAIL because mapping refresh UI/action not present.

**Step 3: Implement DI wiring in `main.dart`**

Add provider chain:
- `ProxyProvider<TushareTokenService, TushareClient>` (or reuse existing creation point)
- `ProxyProvider<TushareClient, SwIndustryIndexMappingService>`

Keep token-empty behavior consistent with existing SW index fetch wiring.

**Step 4: Implement Data Management action**

In `lib/screens/data_management_screen.dart`:
- add a small action in SW section to refresh mapping
- call `SwIndustryIndexMappingService.refreshFromTushare(isNew: 'Y')`
- show snackbar with count and error path

**Step 5: Re-run targeted test**

Run: `flutter test test/screens/data_management_screen_test.dart`

Expected: PASS for new mapping refresh behavior without breaking existing SW index card tests.

**Step 6: Checkpoint**

Record changed files and keep branch uncommitted unless user explicitly requests commit.

---

### Task 4: Add SW daily K-line main chart in industry detail screen

**Files:**
- Modify: `lib/screens/industry_detail_screen.dart`
- (Optional Create): `lib/widgets/industry_sw_daily_kline_card.dart` (only if extraction improves readability)
- Test: `test/screens/industry_detail_screen_test.dart`

**Step 1: Write failing industry detail tests (main chart behavior)**

Add tests in `test/screens/industry_detail_screen_test.dart`:
- shows SW K-line main chart card above EMA breadth card when mapping and bars exist
- shows loading state while K-line is fetching
- shows error/empty fallback when mapping missing or bars empty

Use stable keys:
- `ValueKey('industry_detail_sw_kline_card')`
- `ValueKey('industry_detail_sw_kline_loading')`
- `ValueKey('industry_detail_sw_kline_empty')`

**Step 2: Run test to verify fail**

Run: `flutter test test/screens/industry_detail_screen_test.dart`

Expected: FAIL because SW main chart section is not implemented.

**Step 3: Implement screen state + data loading**

In `IndustryDetailScreen`:
- add state: `_swKlines`, `_isSwKlineLoading`, `_swKlineError`, `_swTsCode`
- on init and industry change, trigger `_loadSwIndustryKline()`
- resolve ts_code from `SwIndustryIndexMappingService.resolveTsCodeByIndustry(widget.industry)`
- build date range: today - 400 days (to cover 260+ trading days), then trim display list to last 260 bars
- load bars from `SwIndexRepository.getDailyKlines(tsCodes: [_swTsCode], dateRange: range)`

**Step 4: Implement main chart UI**

In sliver header chart area:
- replace existing trend card position with SW K-line main card (or insert before trend summary cards)
- render `KLineChart` with `height: 150` (or tuned) and `bars: _swKlines`
- preserve existing EMA breadth card as sub chart below main chart
- update expanded height constants accordingly

**Step 5: Re-run industry detail tests**

Run: `flutter test test/screens/industry_detail_screen_test.dart`

Expected: PASS including new main chart + existing EMA breadth behavior.

**Step 6: Checkpoint**

Record changed files and keep branch uncommitted unless user explicitly requests commit.

---

### Task 5: Regression and integration verification

**Files:**
- Verify only (no new files unless fixes are required)

**Step 1: Run focused tests for touched modules**

Run:
- `flutter test test/services/tushare_client_test.dart`
- `flutter test test/data/repository/sw_index_repository_test.dart`
- `flutter test test/providers/sw_index_data_provider_test.dart`
- `flutter test test/screens/data_management_screen_test.dart`
- `flutter test test/screens/industry_detail_screen_test.dart`

Expected: PASS.

**Step 2: Run static analysis**

Run: `flutter analyze`

Expected: no new errors introduced by this feature.

**Step 3: Run full test suite if time budget allows**

Run: `flutter test`

Expected: all pass, or only pre-existing failures documented.

**Step 4: Prepare delivery notes**

Document:
- exact mapping source (`index_member_all`, `is_new='Y'`, `l1_name -> l1_code`)
- fallback behavior when mapping/data unavailable
- files changed and test evidence
