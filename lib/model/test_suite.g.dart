// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'test_suite.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TestSuite _$TestSuiteFromJson(Map<String, dynamic> json) => TestSuite(
      tableId: json['tableId'] as String,
      testCases: (json['testCases'] as List<dynamic>)
          .map((e) => TestCase.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$TestSuiteToJson(TestSuite instance) => <String, dynamic>{
      'tableId': instance.tableId,
      'testCases': instance.testCases,
    };
