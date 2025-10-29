import 'package:json_annotation/json_annotation.dart';

part 'operator_setting.g.dart';

@JsonSerializable()
class OperatorSetting {
  String name;
  String value;
  String type;

  OperatorSetting({required this.name, required this.value, required this.type});

  factory OperatorSetting.fromJson(Map<String, dynamic> json) =>
      _$OperatorSettingFromJson(json);

  Map<String, dynamic> toJson() => _$OperatorSettingToJson(this);  
}