// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'test_case.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TestCase _$TestCaseFromJson(Map<String, dynamic> json) => TestCase(
      workflowId: json['workflowId'] as String,
      stepId: json['stepId'] as String,
      downsample: (json['downsample'] as num).toDouble(),
    );

Map<String, dynamic> _$TestCaseToJson(TestCase instance) => <String, dynamic>{
      'workflowId': instance.workflowId,
      'stepId': instance.stepId,
      'downsample': instance.downsample,
    };
