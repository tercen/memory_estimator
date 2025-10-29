// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'test_case.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TestCase _$TestCaseFromJson(Map<String, dynamic> json) => TestCase(
      workflowId: json['workflowId'] as String,
      stepId: json['stepId'] as String,
      downsample: (json['downsample'] as num).toDouble(),
      nObs: (json['nObs'] as num).toDouble(),
      nSp: (json['nSp'] as num).toDouble(),
      nVariable: (json['nVariable'] as num).toDouble(),
      settings: (json['settings'] as List<dynamic>)
          .map((e) => OperatorSetting.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$TestCaseToJson(TestCase instance) => <String, dynamic>{
      'workflowId': instance.workflowId,
      'stepId': instance.stepId,
      'downsample': instance.downsample,
      'nObs': instance.nObs,
      'nSp': instance.nSp,
      'nVariable': instance.nVariable,
      'settings': instance.settings,
    };
