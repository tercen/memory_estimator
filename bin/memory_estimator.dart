import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:args/args.dart';
import 'package:uuid/uuid.dart';
import 'package:webapp_core/app/app_session.dart';
import 'package:sci_tercen_client/sci_client.dart' as sci;
import 'package:sci_tercen_client/sci_client_service_factory.dart' as tercen;
import 'package:webapp_core/runner/utils/workflow/workflow_config_utils.dart';
import 'package:webapp_core/runner/workflow_runner.dart';
import 'package:webapp_core/runner/utils/workflow/workflow_settings_utils.dart';
import 'package:webapp_core/runner/utils/workflow/workflow_input_utils.dart';
import 'package:webapp_core/service/file_data_service.dart';
import 'package:webapp_core/service/library_data_service.dart';
import 'package:webapp_core/service/project_data_service.dart';
import 'package:webapp_core/service/user_data_service.dart';
import 'package:webapp_core/utils/string_utils.dart';
import 'package:webapp_core/runner/utils/cache_object.dart';
import 'package:memory_estimator/cube_query_builder.dart';

/// Configuration loaded from memory_tests.json
class MemoryTestConfig {
  final Map<String, dynamic>? dataParams;
  final Map<String, dynamic>? ramLimits;
  final Map<String, String>? operatorSettings;

  MemoryTestConfig({
    this.dataParams,
    this.ramLimits,
    this.operatorSettings,
  });

  factory MemoryTestConfig.fromJson(Map<String, dynamic> json) {
    return MemoryTestConfig(
      dataParams: json['data_params'] as Map<String, dynamic>?,
      ramLimits: json['ram_limits'] as Map<String, dynamic>?,
      operatorSettings: (json['operator_settings'] as Map<String, dynamic>?)
          ?.map((key, value) => MapEntry(key, value.toString())),
    );
  }
}

/// Enumerated property definition from operator.json
class EnumeratedProperty {
  final String name;
  final String defaultValue;
  final List<String> values;

  EnumeratedProperty({
    required this.name,
    required this.defaultValue,
    required this.values,
  });

  factory EnumeratedProperty.fromJson(Map<String, dynamic> json) {
    return EnumeratedProperty(
      name: json['name'] as String,
      defaultValue: json['defaultValue'].toString(),
      values: (json['values'] as List<dynamic>).map((v) => v.toString()).toList(),
    );
  }
}

/// Fetch operator.json from the installed operator project in Tercen
Future<Map<String, EnumeratedProperty>> fetchOperatorEnumerations({
  required String repoUrl,
  required String teamName,
  String? tag,
}) async {
  final tagName = tag ?? "latest";
  final projectName = "$repoUrl@${tagName}_Test";

  print("Fetching operator.json to extract enumeration properties...");

  // Fetch the project
  final project = await ProjectDataService()
      .fetchProjectByName(projectName: projectName, owner: teamName);

  if (project == null) {
    throw Exception(
        "Operator project not found: $projectName. Ensure the operator was installed correctly.");
  }

  // Find the operator.json file in the project
  try {
    final docs = await tercen.ServiceFactory()
        .projectDocumentService
        .findProjectObjectsByFolderAndName(
              startKey: [project.id, '', 'operator.json'],
              endKey: [project.id, '', 'operator.json']);

    final operatorDoc = docs.firstWhere(
      (doc) => doc.name == "operator.json",
      orElse: () => throw Exception(
          "operator.json not found in project $projectName."),
    );

    // Get the file content as stream and convert to bytes
    final stream = tercen.ServiceFactory()
        .fileService
        .download(operatorDoc.id);

    final bytes = await stream.toList();
    final allBytes = bytes.expand((chunk) => chunk).toList();

    // Parse JSON
    final jsonString = utf8.decode(allBytes);
    final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;

    // Extract enumerated properties
    final enumerations = <String, EnumeratedProperty>{};
    final properties = jsonData['properties'] as List<dynamic>?;

    if (properties != null) {
      for (var prop in properties) {
        final propMap = prop as Map<String, dynamic>;
        if (propMap['kind'] == 'EnumeratedProperty') {
          final enumProp = EnumeratedProperty.fromJson(propMap);
          enumerations[enumProp.name] = enumProp;
        }
      }
    }

    print("✓ Found ${enumerations.length} enumerated properties in operator.json");
    return enumerations;
  } catch (e) {
    print("Warning: Could not load operator.json - $e");
    return {};
  }
}

/// Fetch memory_tests.json from the installed operator project in Tercen
Future<MemoryTestConfig> fetchMemoryTestConfig({
  required String repoUrl,
  required String teamName,
  String? tag,
}) async {
  final tagName = tag ?? "latest";
  final projectName = "$repoUrl@${tagName}_Test";

  print("Fetching memory_tests.json from project: $projectName");

  // Fetch the project
  final project = await ProjectDataService()
      .fetchProjectByName(projectName: projectName, owner: teamName);

  if (project == null) {
    throw Exception(
        "Operator project not found: $projectName. Ensure the operator was installed correctly.");
  }

  // Find the memory_tests.json file in the project
  try {

    final docs = await tercen.ServiceFactory()
        .projectDocumentService
        .findProjectObjectsByFolderAndName(
              startKey: [project.id, '', 'memory_tests.json'],
              endKey: [project.id, '', 'memory_tests.json']);

    final memoryTestDoc = docs.firstWhere(
      (doc) => doc.name == "memory_tests.json",
      orElse: () => throw Exception(
          "memory_tests.json not found in project $projectName. This file is required at the root of the operator repository."),
    );


    // Get the file content as stream and convert to bytes
    final stream = tercen.ServiceFactory()
        .fileService
        .download(memoryTestDoc.id);

    final bytes = await stream.toList();
    final allBytes = bytes.expand((chunk) => chunk).toList();

    // Parse JSON
    final jsonString = utf8.decode(allBytes);
    final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;

    print("✓ Successfully loaded memory_tests.json");
    return MemoryTestConfig.fromJson(jsonData);
  } catch (e) {
    if (e.toString().contains("memory_tests.json not found")) {
      rethrow;
    }
    throw Exception("Failed to load or parse memory_tests.json: $e");
  }
}

/// Generate combined grid for data parameters and operator settings
List<Map<String, dynamic>> _generateCombinedGrid({
  required Map<String, List<int>> dataRanges,
  required Map<String, List<double>> settingRanges,
  required Map<String, List<String>> enumRanges,
  required Map<String, String> fixedSettings,
  int? nObsDefault,
  int? nSpDefault,
  int? nVariableDefault,
}) {
  final combinations = <Map<String, dynamic>>[];

  // Combine all parameter names
  final dataParamNames = dataRanges.keys.toList();
  final settingParamNames = settingRanges.keys.toList();
  final enumParamNames = enumRanges.keys.toList();

  void generate(int dataIndex, int settingIndex, int enumIndex, Map<String, dynamic> current) {
    // Done with all params
    if (dataIndex == dataParamNames.length &&
        settingIndex == settingParamNames.length &&
        enumIndex == enumParamNames.length) {
      // Add fixed settings and defaults
      final combo = Map<String, dynamic>.from(current);
      combo.addAll(fixedSettings);

      // Add defaults for data params not in ranges
      if (!combo.containsKey('n_obs') && nObsDefault != null)
        combo['n_obs'] = nObsDefault;
      if (!combo.containsKey('n_sp') && nSpDefault != null)
        combo['n_sp'] = nSpDefault;
      if (!combo.containsKey('n_variable') && nVariableDefault != null)
        combo['n_variable'] = nVariableDefault;

      combinations.add(combo);
      return;
    }

    if (dataIndex < dataParamNames.length) {
      final paramName = dataParamNames[dataIndex];
      final values = dataRanges[paramName]!;

      for (var value in values) {
        final next = Map<String, dynamic>.from(current);
        next[paramName] = value;
        generate(dataIndex + 1, settingIndex, enumIndex, next);
      }
    } else if (settingIndex < settingParamNames.length) {
      final paramName = settingParamNames[settingIndex];
      final values = settingRanges[paramName]!;

      for (var value in values) {
        final next = Map<String, dynamic>.from(current);
        next[paramName] = value == value.toInt()
            ? value.toInt().toString()
            : value.toString();
        generate(dataIndex, settingIndex + 1, enumIndex, next);
      }
    } else if (enumIndex < enumParamNames.length) {
      final paramName = enumParamNames[enumIndex];
      final values = enumRanges[paramName]!;

      for (var value in values) {
        final next = Map<String, dynamic>.from(current);
        next[paramName] = value;
        generate(dataIndex, settingIndex, enumIndex + 1, next);
      }
    }
  }

  generate(0, 0, 0, {});
  return combinations;
}

void main(List<String> arguments) async {
  // Parse command-line arguments
  final parser = ArgParser()
    ..addOption('tercen-url',
        abbr: 'u',
        defaultsTo: 'http://127.0.0.1:5400',
        help: 'Tercen service URL')
    ..addOption('username',
        mandatory: true, help: 'Tercen username (required for authentication)')
    ..addOption('password',
        help: 'Tercen password (required for authentication)')
    ..addOption('repo-url',
        abbr: 'r', mandatory: true, help: 'Github repo of the tested operator')
    ..addOption('repo-version',
        abbr: 't',
        mandatory: false,
        help: 'Github repo version of the tested operator')
    ..addOption('repo-branch',
        abbr: 'b',
        mandatory: false,
        help: 'Github repo branch of the tested operator',
        defaultsTo: "main")
    ..addOption('team-name',
        mandatory: true, help: 'Team name for project and workflow ownership')
    ..addOption('output',
        abbr: 'o', help: 'Output file path to save summary table as CSV')
    ..addFlag('help',
        abbr: 'h', negatable: false, help: 'Show usage information');

  try {
    final results = parser.parse(arguments);

    if (results['help'] as bool) {
      print('Memory Estimator - A tool for estimating memory requirements');
      print(
          '\nUsage: dart run bin/memory_estimator.dart [options]');
      print('\nAll test parameters (data sizes, RAM limits, operator settings) must be');
      print('defined in memory_tests.json in the operator repository.\n');
      print('Options:');
      print(parser.usage);
      return;
    }

    final serviceUri = results['tercen-url'] as String;
    final username = results['username'] as String;
    final password = results['password'] as String?;

    final repoUrl = results['repo-url'] as String;
    final repoVersion = results['repo-version'] as String?;
    final repoBranch = results['repo-branch'] as String;

    final teamName = results['team-name'] as String;
    final outputFile = results['output'] as String?;

    // Initialize Tercen session first
    AppSession appSession = AppSession();
    await appSession.initSession(
        user: username, passw: password, serviceUrl: serviceUri);

    //Set up library team
    // Determine the version string for display and installation
    final versionRef = repoVersion ?? repoBranch;
    print(
        "Setting library 'memory_test_library' with project $repoUrl@$versionRef for user $teamName");
    await UserDataService()
        .createTeam(teamName: "memory_test_library", owner: teamName, isLibrary: true);
    print("\tCreated library team");
    await LibraryDataService.installOperator(
        url: repoUrl,
        team: "memory_test_library",
        branch: repoVersion == null ? repoBranch : null,
        tag: repoVersion);
    print("\tInstalled test project");

    // Load operator.json to get enumeration definitions
    print("\nLoading operator.json...");
    final enumerations = await fetchOperatorEnumerations(
      repoUrl: repoUrl,
      teamName: "memory_test_library",
      tag: repoVersion,
    );

    // Load memory_tests.json from the installed operator project
    print("\nLoading configuration from memory_tests.json...");
    final config = await fetchMemoryTestConfig(
      repoUrl: repoUrl,
      teamName: "memory_test_library",
      tag: repoVersion,
    );

    // Verify config is valid - at least one section must be present
    if (config.dataParams == null &&
        config.ramLimits == null &&
        config.operatorSettings == null) {
      throw Exception(
        "Invalid memory_tests.json: File is empty or missing required sections.\n"
        "The file must contain at least one of: data_params, ram_limits, or operator_settings");
    }

    // Get configuration values from JSON with defaults
    String getConfigValue(String jsonKey, String defaultValue) {
      if (jsonKey.startsWith('data_params.')) {
        final key = jsonKey.substring('data_params.'.length);
        final value = config.dataParams?[key];
        if (value != null) return value.toString();
      } else if (jsonKey.startsWith('ram_limits.')) {
        final key = jsonKey.substring('ram_limits.'.length);
        final value = config.ramLimits?[key];
        if (value != null) return value.toString();
      }
      return defaultValue;
    }

    final minRamMb = double.parse(getConfigValue('ram_limits.min_ram_mb', '500'));
    final maxRamMb = double.parse(getConfigValue('ram_limits.max_ram_mb', '40000'));
    final thresholdMb = double.parse(getConfigValue('ram_limits.threshold_mb', '500'));

    // Get operator settings from JSON only
    final operatorSettings = <String, String>{
      ...?config.operatorSettings,
    };

    // Process operator settings to separate numeric ranges from other settings
    final operatorSettingRanges = <String, List<double>>{};
    final settingsToProcess = <String, String>{...operatorSettings};

    for (var entry in settingsToProcess.entries) {
      final settingName = entry.key;
      final settingValue = entry.value;

      // Check if it's a numeric range (and NOT an enumeration)
      if (settingValue.contains(':') && !enumerations.containsKey(settingName)) {
        final rangeParts = settingValue.split(':');
        if (rangeParts.length == 3) {
          try {
            final min = double.parse(rangeParts[0]);
            final nSteps = int.parse(rangeParts[1]);
            final max = double.parse(rangeParts[2]);

            final values = <double>[];
            if (nSteps == 1) {
              values.add(min);
            } else {
              final step = (max - min) / (nSteps - 1);
              for (int i = 0; i < nSteps; i++) {
                values.add(min + i * step);
              }
            }
            operatorSettingRanges[settingName] = values;
            operatorSettings.remove(settingName);
          } catch (e) {
            // Not a valid numeric range, keep as regular setting
          }
        }
      }
    }

    // Process enumeration settings - expand special syntax
    final enumSettingRanges = <String, List<String>>{};
    final settingsToRemove = <String>[];

    for (var entry in operatorSettings.entries) {
      final settingName = entry.key;
      final settingValue = entry.value;

      // Check if this is an enumeration property
      if (enumerations.containsKey(settingName)) {
        final enumProp = enumerations[settingName]!;

        // Check for special syntax: "*" = all values, or comma-separated list
        if (settingValue == '*') {
          // Test all enum values
          enumSettingRanges[settingName] = List.from(enumProp.values);
          settingsToRemove.add(settingName);
          print("  Enumeration '$settingName': testing all values ${enumProp.values}");
        } else if (settingValue.contains(',')) {
          // Test specific subset of enum values
          final selectedValues = settingValue.split(',').map((v) => v.trim()).toList();
          // Validate all values are valid
          for (var val in selectedValues) {
            if (!enumProp.values.contains(val)) {
              throw Exception(
                "Invalid value '$val' for enumeration '$settingName'. Valid values: ${enumProp.values}");
            }
          }
          enumSettingRanges[settingName] = selectedValues;
          settingsToRemove.add(settingName);
          print("  Enumeration '$settingName': testing values $selectedValues");
        } else {
          // Single value - validate it
          if (!enumProp.values.contains(settingValue)) {
            throw Exception(
              "Invalid value '$settingValue' for enumeration '$settingName'. Valid values: ${enumProp.values}");
          }
        }
      }
    }

    // Remove enumeration settings that have been converted to ranges
    for (var key in settingsToRemove) {
      operatorSettings.remove(key);
    }


    // SETUP Test Project - declare outside try block for cleanup access
    Map<String, String>? projectMap;
    String? projectId;
    String? stepId;
    String? tableStepId;
    String? workflowId;

    try {
      projectMap = await setup(user: teamName, repoUrl: repoUrl);
      projectId = projectMap["projectId"];
      stepId = projectMap["stepId"];
      tableStepId = projectMap["tableStepId"];
      workflowId = projectMap["workflowId"];

      // Parse synthetic data parameters (support ranges) with merged config
      final dataParamRanges = <String, List<int>>{};
      int? nObsSingle;
      int? nSpSingle;
      int? nVariableSingle;

      for (var param in [
        {'key': 'n_obs'},
        {'key': 'n_sp'},
        {'key': 'n_variable'}
      ]) {
        final value = getConfigValue('data_params.${param['key']!}', '');
        if (value.isEmpty) {
          // Use default if not in JSON
          if (param['key'] == 'n_obs') nObsSingle = 500;
          if (param['key'] == 'n_sp') nSpSingle = 4;
          if (param['key'] == 'n_variable') nVariableSingle = 4;
          continue;
        }

        if (value.contains(':')) {
          final parts = value.split(':');
          if (parts.length == 3) {
            final min = int.parse(parts[0]);
            final nSteps = int.parse(parts[1]);
            final max = int.parse(parts[2]);

            final values = <int>[];
            if (nSteps == 1) {
              values.add(min);
            } else {
              final step = (max - min) / (nSteps - 1);
              for (int i = 0; i < nSteps; i++) {
                values.add((min + i * step).round());
              }
            }
            dataParamRanges[param['key']!] = values;
          }
        } else {
          final intValue = int.parse(value);
          if (param['key'] == 'n_obs') nObsSingle = intValue;
          if (param['key'] == 'n_sp') nSpSingle = intValue;
          if (param['key'] == 'n_variable') nVariableSingle = intValue;
        }
      }

      // Validate that at least some test configuration exists
      if (operatorSettingRanges.isEmpty &&
          enumSettingRanges.isEmpty &&
          dataParamRanges.isEmpty &&
          (nObsSingle == null || nSpSingle == null || nVariableSingle == null)) {
        throw Exception(
          "Invalid configuration: No test parameters defined.\n"
          "memory_tests.json must define either:\n"
          "  - Ranges for data_params (e.g., 'n_obs': '500:2:5000')\n"
          "  - Ranges for operator_settings\n"
          "  - Enumeration values for operator properties\n"
          "  - Single values for all required data parameters");
      }

      // Check if we need to do grid search
      if (operatorSettingRanges.isNotEmpty || enumSettingRanges.isNotEmpty || dataParamRanges.isNotEmpty) {
        // Grid search mode
        final totalCombos = (dataParamRanges.values.isEmpty
                ? 1
                : dataParamRanges.values.fold(1, (p, l) => p * l.length)) *
            (operatorSettingRanges.values.isEmpty
                ? 1
                : operatorSettingRanges.values.fold(1, (p, l) => p * l.length)) *
            (enumSettingRanges.values.isEmpty
                ? 1
                : enumSettingRanges.values.fold(1, (p, l) => p * l.length));
        print('Grid search mode: Testing $totalCombos combinations');

        // Generate all combinations
        final combinations = _generateCombinedGrid(
          dataRanges: dataParamRanges,
          settingRanges: operatorSettingRanges,
          enumRanges: enumSettingRanges,
          fixedSettings: operatorSettings,
          nObsDefault: nObsSingle,
          nSpDefault: nSpSingle,
          nVariableDefault: nVariableSingle,
        );

        // Collect all parameter names (data params + operator settings)
        final allParamNames = <String>[];

        // Add data params first (in order)
        if (dataParamRanges.containsKey('n_obs') || nObsSingle != null)
          allParamNames.add('n_obs');
        if (dataParamRanges.containsKey('n_sp') || nSpSingle != null)
          allParamNames.add('n_sp');
        if (dataParamRanges.containsKey('n_variable') ||
            nVariableSingle != null) allParamNames.add('n_variable');

        // Add operator settings params (sorted), prefixed with "settings."
        final settingNames = <String>{
          ...operatorSettingRanges.keys,
          ...enumSettingRanges.keys,
          ...operatorSettings.keys
        }.toList()
          ..sort();
        allParamNames.addAll(settingNames.map((name) => 'settings.$name'));

        // Print CSV header
        print('\n${'=' * 80}');
        print('GRID SEARCH RESULTS');
        print('=' * 80);
        print('${allParamNames.join(',')},estimated_ram_mb,runtime_seconds');

        // Store results for summary table
        final results = <Map<String, dynamic>>[];

        // Run for each combination
        for (int i = 0; i < combinations.length; i++) {
          final combo = combinations[i];
          print('\n--- Combination ${i + 1}/${combinations.length} ---');

          // Extract data params
          final nObs = combo['n_obs'] as int? ?? nObsSingle ?? 500;
          final nSp = combo['n_sp'] as int? ?? nSpSingle ?? 4;
          final nVariable = combo['n_variable'] as int? ?? nVariableSingle ?? 4;

          // Extract operator settings
          final comboSettings = <String, String>{};
          for (var key in combo.keys) {
            if (!['n_obs', 'n_sp', 'n_variable'].contains(key)) {
              comboSettings[key] = combo[key].toString();
            }
          }

          final estimator = MemoryEstimatorScript(
            projectId: projectId!,
            workflowId: workflowId!,
            stepId: stepId!,
            tableStepId: tableStepId!,
            teamName: teamName,
            nObs: nObs,
            nSp: nSp,
            nVariable: nVariable,
            minRamMb: minRamMb,
            maxRamMb: maxRamMb,
            thresholdMb: thresholdMb,
            operatorSettings: comboSettings,
          );

          final result = await estimator.run();
          final ramMb = result['ram']!;
          final runtime = result['time']!;

          // Build result row
          final rowValues = <String>[];
          for (var name in allParamNames) {
            if (name == 'n_obs') {
              rowValues.add(nObs.toString());
            } else if (name == 'n_sp') {
              rowValues.add(nSp.toString());
            } else if (name == 'n_variable') {
              rowValues.add(nVariable.toString());
            } else {
              // Remove "settings." prefix to look up in comboSettings
              final settingKey = name.startsWith('settings.')
                  ? name.substring('settings.'.length)
                  : name;
              rowValues.add(comboSettings[settingKey] ?? '');
            }
          }

          // Print CSV row
          print('${rowValues.join(',')},${ramMb.toStringAsFixed(2)},${runtime.toStringAsFixed(2)}');

          // Store for summary
          final resultMap = <String, dynamic>{};
          for (int j = 0; j < allParamNames.length; j++) {
            resultMap[allParamNames[j]] = rowValues[j];
          }
          resultMap['estimated_ram_mb'] = ramMb;
          resultMap['runtime_seconds'] = runtime;
          results.add(resultMap);
        }

        // Print summary table
        print('\n${'=' * 80}');
        print('SUMMARY TABLE');
        print('=' * 80);
        final csvHeader = '${allParamNames.join(',')},estimated_ram_mb,runtime_seconds';
        print(csvHeader);
        final csvRows = <String>[];
        for (var result in results) {
          final values =
              allParamNames.map((name) => result[name].toString()).join(',');
          final row =
              '$values,${result['estimated_ram_mb'].toStringAsFixed(2)},${result['runtime_seconds'].toStringAsFixed(2)}';
          print(row);
          csvRows.add(row);
        }
        print('=' * 80);

        // Write to output file if specified
        if (outputFile != null) {
          try {
            final file = File(outputFile);
            final csvContent = [csvHeader, ...csvRows].join('\n');
            await file.writeAsString(csvContent);
            print('\nSummary table saved to: $outputFile');
          } catch (e) {
            print('\nWarning: Failed to write output file: $e');
          }
        }
      } else {
        // Single run mode
        if (operatorSettings.isNotEmpty) {
          print('Operator settings:');
          operatorSettings.forEach((key, value) {
            print('  $key = $value');
          });
        }

        final estimator = MemoryEstimatorScript(
          projectId: projectId!,
          workflowId: workflowId!,
          stepId: stepId!,
          tableStepId: tableStepId!,
          teamName: teamName,
          nObs: nObsSingle!,
          nSp: nSpSingle!,
          nVariable: nVariableSingle!,
          minRamMb: minRamMb,
          maxRamMb: maxRamMb,
          thresholdMb: thresholdMb,
          operatorSettings: operatorSettings,
        );

        await estimator.run();
      }
    } catch (e) {
      print("Failed to run memory estimator -- $e");
      rethrow;
    } finally {
      if (projectMap != null) {
        try {
          await cleanup(idMap: projectMap);
        } catch (e) {
          print("Warning: Error during cleanup - $e");
        }
      }
    }
  } on FormatException catch (e) {
    print('Error: ${e.message}\n');
    print('Usage: dart run bin/memory_estimator.dart.bkp [options]');
    print('\nOptions:');
    print(parser.usage);
  }
}

Future<Map<String, String>> setup({
  required String user,
  required String repoUrl,
}) async {
  final project = await ProjectDataService().createProject(
      name: "MemoryTest_${StringUtils.getRandomString(4)}", owner: user);

  var workflow = await WorkflowConfigUtils.copyTemplateFromLibrary(
      templateUrl: repoUrl,
      projectId: project.id,
      user: user,
      workflowName: "memory_workflow");

  final stepId = workflow.steps.whereType<sci.DataStep>().first.id;

  // Set the operator on the workflow step
  workflow = await WorkflowSettingsUtils.setOperator(
      workflow: workflow,
      operatorUrl: repoUrl,
      operatorVersion: "latest",
      stepId: stepId);


  workflow.rev = await tercen.ServiceFactory().workflowService.update(workflow);

  return {
    'projectId': project.id,
    'workflowId': workflow.id,
    'stepId': stepId,
    'tableStepId': workflow.steps.whereType<sci.TableStep>().first.id
  };
}

Future<void> cleanup({required Map<String, String> idMap}) async {
  final project =
      await tercen.ServiceFactory().projectService.get(idMap["projectId"]!);
  await tercen.ServiceFactory().projectService.delete(project.id, project.rev);
}

class MemoryEstimatorScript {
  final String projectId;
  final String workflowId;
  final String stepId;
  final String tableStepId;
  final String? teamName;
  final int nObs;
  final int nSp;
  final int nVariable;
  final double minRamMb;
  final double maxRamMb;
  final double thresholdMb;
  final Map<String, String> operatorSettings;

  MemoryEstimatorScript({
    required this.projectId,
    required this.workflowId,
    required this.stepId,
    required this.tableStepId,
    this.teamName,
    required this.nObs,
    required this.nSp,
    required this.nVariable,
    this.minRamMb = 500,
    this.maxRamMb = 40000,
    this.thresholdMb = 500,
    this.operatorSettings = const {},
  });

  void log(String message) {
    print("[${DateTime.now().toIso8601String()}] $message");
  }

  void logIndent(String message) {
    print("  $message");
  }

  Future<Map<String, double>> run() async {
    log("Initializing memory estimator");

    // Use existing AppSession (already initialized in main)
    final sess = AppSession().session;

    log("Connected to Tercen ${sess.serverVersion.major}.${sess.serverVersion.minor}.${sess.serverVersion.patch}");
    log("User: ${sess.user.id}");

    log("Starting RAM estimation for:");
    logIndent("Workflow ID: $workflowId");
    logIndent("Step ID: $stepId");
    logIndent("Synthetic data: nObs=$nObs, nSp=$nSp, nVariable=$nVariable");

    String? copiedWorkflowId;
    String? syntheticDataId;

    try {
      final result = await estimateRequiredRam(
        onWorkflowCopied: (id) => copiedWorkflowId = id,
        onDataCreated: (id) => syntheticDataId = id,
      );

      final estimatedRam = result[0];
      final runtime = result[1];

      log("═══════════════════════════════════════");
      log("RESULT: Estimated RAM needed: ${estimatedRam.toStringAsFixed(2)} MB");
      log("RESULT: Runtime: ${runtime.toStringAsFixed(2)} seconds");
      log("═══════════════════════════════════════");

      return {'ram': estimatedRam, 'time': runtime};
    } finally {
      // Cleanup
      await cleanup(
        workflowId: copiedWorkflowId,
        dataSchemaId: syntheticDataId,
      );
    }
  }

  Future<void> cleanup({String? workflowId, String? dataSchemaId}) async {
    log("Cleaning up temporary resources...");

    try {
      await Future.delayed(const Duration(seconds: 2));
      CacheObject().clearCache();
      //Disabled for now
      if (workflowId != null) {
        logIndent("Deleting copied workflow: $workflowId");
        final workflow =
            await tercen.ServiceFactory().workflowService.get(workflowId);
        await tercen.ServiceFactory()
            .workflowService
            .delete(workflow.id, workflow.rev);
      }

      if (dataSchemaId != null) {
        logIndent("Deleting synthetic data: $dataSchemaId");
        final schema =
            await tercen.ServiceFactory().tableSchemaService.get(dataSchemaId);
        await tercen.ServiceFactory()
            .persistentService
            .delete(schema.id, schema.rev);
      }

      // Also clean up any temporary files in the project
      final objs = await ProjectDataService().fetchProjectObjects(
          projectId: projectId, includeFolders: false, useCache: false);
      final tempFiles = objs.where((obj) => obj.name.startsWith("tmp_synth_"));
      for (var file in tempFiles) {
        logIndent("Deleting temporary file: ${file.name}");
        await tercen.ServiceFactory()
            .persistentService
            .delete(file.id, file.rev);
      }

      CacheObject().clearCache();
      log("Cleanup complete");
    } catch (e) {
      log("Warning: Cleanup failed - $e");
    }
  }

  Future<sci.Relation> createSyntheticData({
    required String projectId,
    required String owner,
  }) async {
    log("Generating synthetic data...");

    final uniqueSp = <String>[];
    final uniqueVariable = <String>[];
    final uniqueSex = ['M', 'F'];

    for (var i = 0; i < nSp; i++) {
      uniqueSp.add(StringUtils.getRandomString(3));
    }
    for (var i = 0; i < nVariable; i++) {
      uniqueVariable.add(StringUtils.getRandomString(3));
    }

    // Create temporary file
    final tempDir = Directory.systemTemp;
    final filename = "tmp_synth_${StringUtils.getRandomString(8)}.csv";
    final tempFile = File('${tempDir.path}/$filename');

    logIndent("Writing data to temporary file: ${tempFile.path}");

    // Write to file using IOSink for streaming
    final sink = tempFile.openWrite();
    sink.writeln("sp,sex,index,observation,variable,measurement");

    var index = 0;
    for (var oi = 0; oi < nObs; oi++) {
      for (var si = 0; si < nSp; si++) {
        for (var vi = 0; vi < nVariable; vi++) {
          for (var gi = 0; gi < uniqueSex.length; gi++) {
            var meas = Random().nextDouble() *
                25 *
                (gi == 0 ? 1 - Random().nextDouble() / 5 : 1.0);

            sink.writeln(
                "'${uniqueSp[si]}','${uniqueSex[gi]}',${index}.0,${oi}.0,'${uniqueVariable[vi]}',$meas");
            index = index + 1;
          }
        }
      }
    }

    await sink.flush();
    await sink.close();

    logIndent("Uploading as: $filename");

    // Read file and upload
    final fileBytes = await tempFile.readAsBytes();
    var schemaId = await FileDataService().uploadFileAsTable2(
        projectId: projectId,
        filename: filename,
        owner: owner,
        data: fileBytes);

    // Clean up temporary file
    await tempFile.delete();

    var sch = await tercen.ServiceFactory().tableSchemaService.get(schemaId);

    final colNames = sch.columns.map((col) => col.name).toSet().toList();

    var refRel = sci.SimpleRelation()..id = schemaId;

    var renameRel = sci.RenameRelation.json({
      "id": "rename_${Uuid().v4()}",
      "inNames": colNames,
      "outNames": colNames,
      "relation": refRel.toJson()
    });

    logIndent("Synthetic data created: $schemaId");
    return renameRel;
  }

  Future<List<double>> estimateRequiredRam({
    required void Function(String) onWorkflowCopied,
    required void Function(String) onDataCreated,
  }) async {
    final mb = 1e6;
    final runner = WorkflowRunner();

    // Get session for owner info
    final sess = AppSession().session;
    final owner = teamName ?? sess.user.id;

    // Load and copy the workflow
    log("Copying workflow to project...");
    var workflow = await runner.copyToProject(
      projectId: projectId,
      workflowId: workflowId,
      teamName: owner,
      workflowName: "tmp_mem_est_${StringUtils.getRandomString(6)}",
    );
    onWorkflowCopied(workflow.id);
    logIndent("Workflow copied: ${workflow.id}");

    // Create synthetic data
    final dataRel = await createSyntheticData(
      projectId: projectId,
      owner: workflow.acl.owner,
    );

    // Extract schema ID for cleanup
    if (dataRel is sci.RenameRelation) {
      final simpleRel = dataRel.relation as sci.SimpleRelation;
      onDataCreated(simpleRel.id);
    }

    // Inject synthetic data into the table step
    log("Injecting synthetic data into workflow...");
    workflow = WorkflowInputUtils().relationToTableStep(
      workflow: workflow,
      stepId: tableStepId,
      relation: dataRel,
    );
    workflow = await runner.saveWorkflow(workflow: workflow);
    logIndent("Data injected into table step: $tableStepId");

    // Update CubeQueryTask
    log("Updating CubeQueryTask...");
    workflow = await _updateCubeQueryTask(
      workflow: workflow,
      stepId: stepId,
      nObs: nObs,
      dataRelation: dataRel,
    );
    logIndent("CubeQueryTask updated");

    // Find the step to test
    final step = workflow.steps
        .whereType<sci.DataStep>()
        .where((s) => s.id == stepId)
        .firstOrNull;

    if (step == null) {
      throw Exception("Step $stepId not found in workflow ${workflow.id}");
    }

    logIndent("Found step: ${step.name}");

    // Save workflow before starting RAM estimation
    workflow = await runner.saveWorkflow(workflow: workflow);

    // PHASE 1: Exponential Search - Find upper bound quickly
    log("Phase 1: Exponential search to find upper bound...");
    var ram = minRamMb * mb;
    var lowerBound = ram;
    var upperBound = maxRamMb * mb;
    var growthFactor = 1.5; // Increase by 50% each iteration
    var currentTime = -1.0;

    while (ram < maxRamMb * mb) {
      final ramMb = ram / mb;
      logIndent("Testing with ${ramMb.toStringAsFixed(2)} MB...");

      // Update the RAM setting for the step
      workflow = WorkflowSettingsUtils.updateEnv(
          workflow: workflow, stepId: stepId, env: "ram", value: "$ram");

      // Reset and run the step
      workflow = await runner.runWorkflow(
          workflow: workflow,
          persistentEvents: false,
          saveAfterRun: false,
          stepsToReset: [stepId],
          stepsToRun: [stepId]);

      // Check if the step succeeded or failed
      final step = workflow.steps
          .whereType<sci.DataStep>()
          .where((s) => s.id == stepId)
          .first;
      final stepState = step.state.taskState;

      if (stepState is sci.FailedState) {
        // Check if it's a memory error
        final isMemoryError = stepState.error == "run.operator.exit.code.137" &&
            stepState.reason.contains("increase memory resources");

        if (isMemoryError) {
          logIndent("  → Insufficient memory, increasing exponentially...");
          lowerBound = ram;
          ram = ram * growthFactor;
        } else {
          logIndent("  → Failed with error: ${stepState.error}");
          throw Exception(
              "Step failed with non-memory error: ${stepState.error} - ${stepState.reason}");
        }
      } else if (stepState is sci.DoneState) {
        logIndent("  → Success! Found upper bound.");
        upperBound = ram;
        // Capture the runtime from this successful run
        final task = await tercen.ServiceFactory().taskService.get(step.state.taskId) as sci.RunComputationTask;
        currentTime = task.duration;
        break;
      } else {
        logIndent("  → Unexpected state: ${stepState.runtimeType}");
        throw Exception("Unexpected step state: ${stepState.runtimeType}");
      }
    }

    if (upperBound >= maxRamMb * mb) {
      log("WARNING: Reached maximum RAM limit of ${maxRamMb} MB in exponential phase");
      return [maxRamMb, -1];
    }

    // PHASE 2: Binary Search - Find precise minimum
    log("Phase 2: Binary search for precise minimum...");
    logIndent(
        "Range: ${(lowerBound / mb).toStringAsFixed(2)} MB - ${(upperBound / mb).toStringAsFixed(2)} MB");

    var currentMin = lowerBound;
    var currentMax = upperBound;
    var stopThreshold = thresholdMb * mb;

    while (true) {
      final delta = currentMax - currentMin;
      if (delta < stopThreshold) {
        logIndent(
            "Converged! Delta: ${(delta / mb).toStringAsFixed(2)} MB < ${thresholdMb} MB");
        break;
      }

      ram = currentMin + (currentMax - currentMin) / 2;
      final ramMb = ram / mb;

      logIndent("Testing with ${ramMb.toStringAsFixed(2)} MB...");

      // Update the RAM setting for the step
      workflow = WorkflowSettingsUtils.updateEnv(
          workflow: workflow, stepId: stepId, env: "ram", value: "$ram");

      // Reset and run the step
      workflow = await runner.runWorkflow(
          workflow: workflow,
          persistentEvents: false,
          saveAfterRun: false,
          stepsToReset: [stepId],
          stepsToRun: [stepId]);

      // Check if the step succeeded or failed
      final step = workflow.steps
          .whereType<sci.DataStep>()
          .where((s) => s.id == stepId)
          .first;
      final stepState = step.state.taskState;

      if (stepState is sci.FailedState) {
        // Check if it's a memory error
        final isMemoryError = stepState.error == "run.operator.exit.code.137" &&
            stepState.reason.contains("increase memory resources");

        if (isMemoryError) {
          logIndent("  → Insufficient memory, increasing...");
          currentMin = ram;
        } else {
          logIndent("  → Failed with error: ${stepState.error}");
          throw Exception(
              "Step failed with non-memory error: ${stepState.error} - ${stepState.reason}");
        }
      } else if (stepState is sci.DoneState) {
        logIndent("  → Success! Decreasing RAM to find minimum...");
        currentMax = ram;
        // Capture the runtime from this successful run
        final task = await tercen.ServiceFactory().taskService.get(step.state.taskId) as sci.RunComputationTask;
        currentTime = task.duration;
      } else {
        logIndent("  → Unexpected state: ${stepState.runtimeType}");
        throw Exception("Unexpected step state: ${stepState.runtimeType}");
      }
    }

    return [currentMax / mb, currentTime];
  }

  Future<sci.Workflow> _updateCubeQueryTask({
    required sci.Workflow workflow,
    required String stepId,
    required int nObs,
    required sci.Relation dataRelation,
  }) async {
    final step = workflow.steps
        .whereType<sci.DataStep>()
        .where((step) => step.id == stepId)
        .firstOrNull;

    if (step == null) {
      throw sci.ServiceError(500, "step.not.found",
          "Step $stepId not found in workflow ${workflow.name} (${workflow.id})");
    }

    // Apply operator settings to the workflow step BEFORE building task
    if (operatorSettings.isNotEmpty) {
      logIndent("Applying operator settings to step...");
      for (var entry in operatorSettings.entries) {
        final settingName = entry.key;
        final settingValue = entry.value;

        try {
          workflow = WorkflowSettingsUtils().updateSetting(
            workflow: workflow,
            stepId: stepId,
            settingName: settingName,
            value: settingValue,
          );
          logIndent("  $settingName = $settingValue");
        } catch (e) {
          logIndent("  Warning: Could not set $settingName - $e");
        }
      }
    }

    // Build task with the synthetic data relation
    var task = CubeQueryBuilder.createTask(
      step,
      projectId: workflow.projectId,
      owner: workflow.acl.owner,
      relation: dataRelation,
    );

    task = (await tercen.ServiceFactory().taskService.create(task))
        as sci.CubeQueryTask;
    await tercen.ServiceFactory().taskService.runTask(task.id);
    await tercen.ServiceFactory().taskService.waitDone(task.id)
        as sci.CubeQueryTask;
    step.model.taskId = task.id;

    if (step.model.axis.xyAxis.first.xAxis.graphicalFactor.factor.name ==
        "observation") {
      step.model.axis.xyAxis.first.xAxis.axisExtent.x =
          step.model.axis.xyAxis.first.xAxis.axisExtent.x + 1;
    }

    workflow.rev =
        await tercen.ServiceFactory().workflowService.update(workflow);

    return workflow;
  }
}
