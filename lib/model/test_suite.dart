import 'package:json_annotation/json_annotation.dart';
import 'package:memory_estimator/model/test_case.dart';

part 'test_suite.g.dart';

@JsonSerializable()
class TestSuite {
  List<TestCase> testCases;

  TestSuite(
      {required this.testCases});

  factory TestSuite.fromJson(Map<String, dynamic> json) =>
      _$TestSuiteFromJson(json);

  Map<String, dynamic> toJson() => _$TestSuiteToJson(this);
}
