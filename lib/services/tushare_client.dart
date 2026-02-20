import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:stock_rtwatcher/models/sw_daily_bar.dart';
import 'package:stock_rtwatcher/models/sw_industry_l1_member.dart';

typedef PostJsonFn =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> payload);

class TushareApiException implements Exception {
  final int code;
  final String message;

  const TushareApiException({required this.code, required this.message});

  @override
  String toString() => 'TushareApiException(code=$code, message=$message)';
}

class TushareClient {
  static const String _baseUrl = 'https://api.tushare.pro';

  final String token;
  final PostJsonFn? _postJsonOverride;
  final http.Client _httpClient;

  TushareClient({
    required this.token,
    PostJsonFn? postJson,
    http.Client? httpClient,
  }) : _postJsonOverride = postJson,
       _httpClient = httpClient ?? http.Client() {
    if (token.trim().isEmpty) {
      throw ArgumentError.value(token, 'token', 'token cannot be empty');
    }
  }

  Map<String, dynamic> buildRequestEnvelope({
    required String apiName,
    Map<String, dynamic>? params,
    String? fields,
  }) {
    return {
      'api_name': apiName,
      'token': token,
      'params': params ?? <String, dynamic>{},
      'fields': fields,
    };
  }

  Future<List<SwDailyBar>> fetchSwDaily({
    required String tsCode,
    required String startDate,
    required String endDate,
    String fields = 'ts_code,trade_date,open,high,low,close,vol,amount',
  }) async {
    final payload = buildRequestEnvelope(
      apiName: 'sw_daily',
      params: {'ts_code': tsCode, 'start_date': startDate, 'end_date': endDate},
      fields: fields,
    );

    final jsonMap = await _postJson(payload);
    final code = (jsonMap['code'] as num?)?.toInt() ?? -1;
    if (code != 0) {
      throw TushareApiException(
        code: code,
        message: jsonMap['msg']?.toString() ?? 'unknown error',
      );
    }

    return parseSwDailyResponse(jsonMap);
  }

  Future<List<SwIndustryL1Member>> fetchSwIndustryMembers({
    String isNew = 'Y',
  }) async {
    final payload = buildRequestEnvelope(
      apiName: 'index_member_all',
      params: {'is_new': isNew},
    );

    final jsonMap = await _postJson(payload);
    final code = (jsonMap['code'] as num?)?.toInt() ?? -1;
    if (code != 0) {
      throw TushareApiException(
        code: code,
        message: jsonMap['msg']?.toString() ?? 'unknown error',
      );
    }

    return parseSwIndustryMembersResponse(jsonMap);
  }

  List<SwDailyBar> parseSwDailyResponse(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      return const <SwDailyBar>[];
    }

    final fieldsRaw = data['fields'];
    final itemsRaw = data['items'];
    if (fieldsRaw is! List || itemsRaw is! List) {
      return const <SwDailyBar>[];
    }

    final fieldNames = fieldsRaw
        .map((e) => e.toString())
        .toList(growable: false);
    final bars = <SwDailyBar>[];
    for (final rowRaw in itemsRaw) {
      if (rowRaw is! List) {
        continue;
      }
      final map = <String, dynamic>{};
      final max = rowRaw.length < fieldNames.length
          ? rowRaw.length
          : fieldNames.length;
      for (var i = 0; i < max; i++) {
        map[fieldNames[i]] = rowRaw[i];
      }
      bars.add(SwDailyBar.fromTushareMap(map));
    }
    return bars;
  }

  List<SwIndustryL1Member> parseSwIndustryMembersResponse(
    Map<String, dynamic> response,
  ) {
    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      return const <SwIndustryL1Member>[];
    }

    final fieldsRaw = data['fields'];
    final itemsRaw = data['items'];
    if (fieldsRaw is! List || itemsRaw is! List) {
      return const <SwIndustryL1Member>[];
    }

    final fieldNames = fieldsRaw
        .map((e) => e.toString())
        .toList(growable: false);
    final rows = <SwIndustryL1Member>[];
    for (final rowRaw in itemsRaw) {
      if (rowRaw is! List) {
        continue;
      }
      final map = <String, dynamic>{};
      final max = rowRaw.length < fieldNames.length
          ? rowRaw.length
          : fieldNames.length;
      for (var i = 0; i < max; i++) {
        map[fieldNames[i]] = rowRaw[i];
      }
      rows.add(SwIndustryL1Member.fromTushareMap(map));
    }
    return rows;
  }

  Future<Map<String, dynamic>> _postJson(Map<String, dynamic> payload) async {
    if (_postJsonOverride != null) {
      return _postJsonOverride!(payload);
    }

    final response = await _httpClient
        .post(
          Uri.parse(_baseUrl),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw TushareApiException(
        code: response.statusCode,
        message: 'HTTP ${response.statusCode}',
      );
    }

    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw const TushareApiException(code: -1, message: 'Invalid response');
    }
    return data;
  }

  void dispose() {
    _httpClient.close();
  }
}
