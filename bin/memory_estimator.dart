import 'dart:async';
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



/// Generate combined grid for data parameters and operator settings
List<Map<String, dynamic>> _generateCombinedGrid({
  required Map<String, List<int>> dataRanges,
  required Map<String, List<double>> settingRanges,
  required Map<String, String> fixedSettings,
  int? nObsDefault,
  int? nSpDefault,
  int? nVariableDefault,
}) {
  final combinations = <Map<String, dynamic>>[];

  // Combine all parameter names
  final dataParamNames = dataRanges.keys.toList();
  final settingParamNames = settingRanges.keys.toList();

  void generate(int dataIndex, int settingIndex, Map<String, dynamic> current) {
    // Done with data params, move to settings
    if (dataIndex == dataParamNames.length &&
        settingIndex == settingParamNames.length) {
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
        generate(dataIndex + 1, settingIndex, next);
      }
    } else if (settingIndex < settingParamNames.length) {
      final paramName = settingParamNames[settingIndex];
      final values = settingRanges[paramName]!;

      for (var value in values) {
        final next = Map<String, dynamic>.from(current);
        next[paramName] = value == value.toInt()
            ? value.toInt().toString()
            : value.toString();
        generate(dataIndex, settingIndex + 1, next);
      }
    }
  }

  generate(0, 0, {});
  return combinations;
}

void main(List<String> arguments) async {
  // Parse command-line arguments
  // Updated lib
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
        help: 'Github repo version of the tested operator',
        defaultsTo: "main")
    ..addOption('team-name',
        mandatory: true, help: 'Team name for workflow copy')
    ..addOption('n-obs',
        defaultsTo: '500',
        help: 'Number of observations (default: 500, or min:n:max for range)')
    ..addOption('n-sp',
        defaultsTo: '4',
        help: 'Number of species (default: 4, or min:n:max for range)')
    ..addOption('n-variable',
        defaultsTo: '4',
        help: 'Number of variables (default: 4, or min:n:max for range)')
    ..addOption('min-ram',
        defaultsTo: '500', help: 'Minimum RAM to test in MB (default: 500)')
    ..addOption('max-ram',
        defaultsTo: '40000', help: 'Maximum RAM to test in MB (default: 40000)')
    ..addOption('threshold',
        defaultsTo: '500', help: 'Stop threshold in MB (default: 500)')
    ..addOption('output',
        abbr: 'o', help: 'Output file path to save summary table as CSV')
    ..addFlag('help',
        abbr: 'h', negatable: false, help: 'Show usage information');

  try {
    // Extract operator settings from arguments with 'setting.' prefix BEFORE parsing
    final operatorSettings = <String, String>{};
    final operatorSettingRanges = <String, List<double>>{};
    final cleanArguments = <String>[];

    for (var arg in arguments) {
      if (arg.startsWith('--setting.')) {
        final parts = arg.substring(2).split('=');
        if (parts.length == 2) {
          final settingName = parts[0].substring('setting.'.length);
          final settingValue = parts[1];

          // Check if it's a range specification (min:n_steps:max)
          if (settingValue.contains(':')) {
            final rangeParts = settingValue.split(':');
            if (rangeParts.length == 3) {
              final min = double.parse(rangeParts[0]);
              final nSteps = int.parse(rangeParts[1]);
              final max = double.parse(rangeParts[2]);

              // Generate values
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
            } else {
              operatorSettings[settingName] = settingValue;
            }
          } else {
            operatorSettings[settingName] = settingValue;
          }
        }
      } else {
        cleanArguments.add(arg);
      }
    }

    final results = parser.parse(cleanArguments);

    if (results['help'] as bool) {
      print('Memory Estimator - A tool for estimating memory requirements');
      print(
          '\nUsage: dart run bin/memory_estimator.dart.bkp [options] [--setting.NAME=VALUE ...]');
      print('\nOptions:');
      print(parser.usage);
      print('\nOperator Settings:');
      print(
          '  --setting.NAME=VALUE         Set operator setting NAME to VALUE');
      print(
          '  --setting.NAME=min:n:max     Test range from min to max with n values');
      print(
          '                               (performs grid search for all combinations)');
      print('');
      print('  Examples:');
      print('    --setting.k_neighbors=5');
      print('    --setting.k_neighbors=5:3:15     # Tests values: 5, 10, 15');
      print(
          '    --setting.alpha=0.1:5:0.9        # Tests 5 values from 0.1 to 0.9');
      print('    --setting.metric=euclidean --setting.k=3:4:10  # Grid search');
      return;
    }

    final serviceUri = results['tercen-url'] as String;
    final username = results['username'] as String;
    final password = results['password'] as String?;

    final repoUrl = results['repo-url'] as String;
    final repoVersion = results['repo-version'] as String?;
    final repoBranch = results['repo-branch'] as String;

    final teamName = results['team-name'] as String;
    final minRamMb = double.parse(results['min-ram'] as String);
    final maxRamMb = double.parse(results['max-ram'] as String);
    final thresholdMb = double.parse(results['threshold'] as String);
    final outputFile = results['output'] as String?;

    // Initialize Tercen session first
    AppSession appSession = AppSession();
    await appSession.initSession(
        user: username, passw: password, serviceUrl: serviceUri);

    //Set up library team
    print(
        "Setting library 'memory_test_library' with project $repoUrl@${repoVersion ?? "main"} for user $teamName");
    await UserDataService()
        .createTeam(teamName: "memory_test_library", owner: teamName, isLibrary: true);
    print("\tCreated library team");
    await LibraryDataService.installOperator(
        url: repoUrl,
        team: "memory_test_library",
        branch: repoBranch,
        tag: repoVersion);
    print("\tInstalled test project");


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

      // Parse synthetic data parameters (support ranges)
      final dataParamRanges = <String, List<int>>{};
      int? nObsSingle;
      int? nSpSingle;
      int? nVariableSingle;

      for (var param in [
        {'name': 'n-obs', 'key': 'n_obs'},
        {'name': 'n-sp', 'key': 'n_sp'},
        {'name': 'n-variable', 'key': 'n_variable'}
      ]) {
        final value = results[param['name']!] as String;
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

      // Check if we need to do grid search
      if (operatorSettingRanges.isNotEmpty || dataParamRanges.isNotEmpty) {
        // Grid search mode
        final totalCombos = (dataParamRanges.values.isEmpty
                ? 1
                : dataParamRanges.values.fold(1, (p, l) => p * l.length)) *
            (operatorSettingRanges.values.isEmpty
                ? 1
                : operatorSettingRanges.values.fold(1, (p, l) => p * l.length));
        print('Grid search mode: Testing $totalCombos combinations');

        // Generate all combinations
        final combinations = _generateCombinedGrid(
          dataRanges: dataParamRanges,
          settingRanges: operatorSettingRanges,
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
