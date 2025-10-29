// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'operator_setting.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OperatorSetting _$OperatorSettingFromJson(Map<String, dynamic> json) =>
    OperatorSetting(
      name: json['name'] as String,
      value: json['value'] as String,
      type: json['type'] as String,
    );

Map<String, dynamic> _$OperatorSettingToJson(OperatorSetting instance) =>
    <String, dynamic>{
      'name': instance.name,
      'value': instance.value,
      'type': instance.type,
    };
