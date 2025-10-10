import 'package:json_annotation/json_annotation.dart';

part 'test_case.g.dart';

@JsonSerializable()
class TestCase {
  String workflowId;
  String stepId;
  double downsample;

  TestCase({required this.workflowId, required this.stepId, required this.downsample});

  factory TestCase.fromJson(Map<String, dynamic> json) =>
      _$TestCaseFromJson(json);

  Map<String, dynamic> toJson() => _$TestCaseToJson(this);  
}