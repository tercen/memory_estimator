import 'package:json_annotation/json_annotation.dart';
import 'package:memory_estimator/model/operator_setting.dart';

part 'test_case.g.dart';

@JsonSerializable()
class TestCase {
  String workflowId;
  String stepId;
  double downsample;
  double nObs;
  double nSp;
  double nVariable;
  List<OperatorSetting> settings;

  TestCase({required this.workflowId, required this.stepId, required this.downsample, required this.nObs,
  required this.nSp, required this.nVariable, required this.settings});

  factory TestCase.fromJson(Map<String, dynamic> json) =>
      _$TestCaseFromJson(json);

  Map<String, dynamic> toJson() => _$TestCaseToJson(this);  
}