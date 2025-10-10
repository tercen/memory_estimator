import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:html' as html;
import 'dart:math';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:json_string/json_string.dart';
import 'package:memory_estimator/model/test_case.dart';
import 'package:memory_estimator/model/test_suite.dart';
import 'package:webapp_core/app/app_session.dart';
import 'package:sci_tercen_client/sci_client.dart' as sci;
import 'package:sci_tercen_client/sci_client_service_factory.dart' as tercen;
import 'package:webapp_core/runner/utils/workflow/workflow_settings_utils.dart';
import 'package:webapp_core/runner/utils/workflow/workflow_filter_utils.dart';
import 'package:webapp_core/runner/utils/workflow/workflow_input_utils.dart';
import 'package:webapp_core/service/workflow_data_service.dart';
import 'package:webapp_core/service/file_data_service.dart';
import 'package:webapp_core/service/project_data_service.dart';
import 'package:webapp_core/runner/workflow_runner.dart';
import 'package:webapp_utils/functions/string_utils.dart';

void main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();

  final estimator = MemoryEstimator();
  print("Starting memory estimator");
  try{
    await estimator.runTests();
  }catch (e){
    print("Failed to initialize -- $e ");
  }
  
  // await estimator.init().then((_) => estimator.runEstimation());
  
  // Close browser window after execution completes
  html.window.close();
}




class MemoryEstimator {
  // final Stopwatch totalStopwatch = Stopwatch();
  final Stopwatch partialStopwatch = Stopwatch();
  MemoryEstimator();

  void done(){
    print( "\t ... DONE in ${partialStopwatch.elapsedMilliseconds} ms \n" );
    partialStopwatch.reset();
  }

  void logAdd(String message){
    print( "\t$message" );
  }

  void log(String message){
    print( "[${DateTime.now().toIso8601String()} ] $message" );
  }

  Future<Map<String,double>> _runTestCase({required String projectId, required TestCase test}) async{
    final workflowId = test.workflowId;
    final stepId = test.stepId;


    log("Copying workflow to project");
    final runner = WorkflowRunner();
    var workflow = await runner.copyToProject(projectId: projectId, workflowId: workflowId, teamName: "team1", workflowName: "New Workflow name");
    done();

    final dataRel = await _createFakeCrabsData(projectId: projectId, filename: "SynthData.csv", owner: workflow.acl.owner);
    //TODO pass to config
    workflow = WorkflowInputUtils().relationToTableStep(workflow: workflow, stepId: "0396dda7-fae2-4ffd-865b-4cee6a25cb06", relation: dataRel);
    workflow =  WorkflowFilterUtils().updateFilterValue(filterName: "SamplePct", workflow: workflow, stepId: stepId, newValue: test.downsample.toString(), factorName: "ds00.random_percentage" );
    workflow = await runner.saveWorkflow(workflow: workflow);

    await updateCubeQueryTask(workflow: workflow, stepId: stepId, removeRows: true, removeColumns: true);
    final sizeMap = <String, double>{};
    sizeMap.addAll(  await extractProjectionSize(workflow: workflow, stepId: stepId, currentMap: sizeMap) );


    log("Starting memory estimation for:");
    

    bool isFinished = false;
    final mb = 1e6;
    
    var ram = 10 * mb;


    double maxRam = 32000*mb;
    var currentMax = maxRam;
    var currentMin = 0.0;
    var stopThr = 50*mb;

    while(!isFinished){
      logAdd("Testing ${ram/mb} mb");
      workflow = WorkflowSettingsUtils.updateEnv(
        workflow: workflow,
        stepId: stepId,
        env: "ram",
        value: "$ram"
      );


      workflow = await runner.runWorkflow(workflow: workflow, persistentEvents: false, saveAfterRun: false, stepsToReset: ["f347ba91-2f19-45c2-9772-08814a1e2159", stepId], stepsToRun: [stepId]);
      final workflowStatus = getWorkflowState(workflow: workflow);
      if( workflowStatus == "SUCCESS"){
        logAdd("Memory is sufficient, trying with less memory");
        currentMax = ram;
        final memAdjust = (currentMax-currentMin)/2;
        if( memAdjust < stopThr){
          logAdd("Minimum delta reached. Stopping.");  
          break;
        }
        ram = ram - memAdjust;
      }else{
        logAdd("Memory is insufficient, increasing memory");
        currentMin = ram;
        final memAdjust = (currentMax-currentMin)/2;
        
        if( memAdjust < stopThr){
          logAdd("Minimum delta reached. Stopping.");  
          break;
        }
        ram = ram + memAdjust;
        if( ram > maxRam){
          print("Estimated memory would be higher than the maximum of ${maxRam/mb}mb. Abort");
          break;
        }
        
      }

    }

    log("Estimated ${currentMax/mb}MB are needed for:");
    
    sizeMap["ram"] = currentMax;

    for( var entry in sizeMap.entries ){
      logAdd(">> ${entry.key} : ${entry.value}");
    }

    //TODO Move to WorkflowDataService
    await tercen.ServiceFactory().workflowService.delete(workflow.id, workflow.rev);
    return sizeMap;
  }

  Future<void> runTests() async {
    
    partialStopwatch.start();
    final serviceUri = const String.fromEnvironment("TERCEN_URL", defaultValue: "http://127.0.0.1:5400");
    final projectId = const String.fromEnvironment("PROJECT_ID", defaultValue: "b6f4910eac19c2cdb3d318ef0a1fae31");
    final testSuite = TestSuite.fromJson(JsonString(await rootBundle.loadString("assets/base_test.json")).decodedValueAsMap);  
    log("Initializing memory estimator with:\n\t * Service URL: ${serviceUri}\n\t * Project Id: ${projectId}");
    AppSession appSession = AppSession();
    await appSession.initSession();
    final sess = appSession.session;
    logAdd("Connected to Tercen ${sess.serverVersion.major}.${sess.serverVersion.minor}.${sess.serverVersion.patch}");
    done();

    bool firstRun = true;
    var est = "";
    for( var test in testSuite.testCases ){
      final map = await _runTestCase(projectId: projectId, test: test);
      if( firstRun ){
        for( var entry in map.entries ){
          est = "$est\t${entry.key}";
        }  
        est="$est\n";
        firstRun = false;
      }
      for( var entry in map.entries ){
        est = "$est\t${entry.value}";
      }
      est="$est\n";
    }

    print("==============================");
    print("MEMORY ESTIMATION TABLE");
    print("==============================\n");
    print(est);



    
  }

  
  Future< Map<String, double> > extractProjectionSize({required sci.Workflow workflow, required String stepId, required Map<String, double> currentMap}) async {
    final step = workflow.steps.whereType<sci.DataStep>().where((step) => step.id == stepId).firstOrNull;

    if( step == null ){
      throw sci.ServiceError(500, "step.not.found", "Step $step not found in workflow ${workflow.name} (${workflow.id}). Aborting");
    }
    
    final cbTask = (await tercen.ServiceFactory().taskService.get(  step.model.taskId )) as sci.CubeQueryTask;
    final schemas = await tercen.ServiceFactory().tableSchemaService.findByQueryHash([cbTask.query.qtHash, cbTask.query.columnHash, cbTask.query.rowHash]);

    currentMap["qt"] = schemas[0].nRows as double;
    currentMap["col"] = schemas[1].nRows as double;
    currentMap["row"] = schemas[2].nRows as double;

    return currentMap;
  }

  Future<sci.Workflow> updateCubeQueryTask({required sci.Workflow workflow, required String stepId, bool removeColumns = false, bool removeRows = false}) async {
    final step = workflow.steps.whereType<sci.DataStep>().where((step) => step.id == stepId).firstOrNull;

    if( step == null ){
      throw sci.ServiceError(500, "step.not.found", "Step $step not found in workflow ${workflow.name} (${workflow.id}). Aborting");
    }
    final cbTask = (await tercen.ServiceFactory().taskService.get(  step.model.taskId )) as sci.CubeQueryTask;

    // var caq = sci.CubeAxisQuery();
    // caq.yAxis = sci.Factor.json({"name":"measurement", "type":"double"});
    // caq.xAxis = sci.Factor.json({"name":"measurement", "type":"double"});
    // var query = sci.CubeQuery();
    // query.axisQueries.add(caq); 
    // query.rowColumns.clear();
    // query.colColumns.clear();
    // query.relation = cbTask.query.relation;
    
    cbTask.query.filters = step.model.filters;
    // print(step.model.toJson())    ;
    var task = sci.CubeQueryTask();
    task.query = cbTask.query;
    // task.schemaIds.addAll( cbTask.schemaIds);
    task.state = sci.InitState();
    task.projectId = workflow.projectId;
    task.owner = workflow.acl.owner;

    task = (await tercen.ServiceFactory().taskService.create(task) )as sci.CubeQueryTask;
    await tercen.ServiceFactory().taskService.runTask(task.id);
    await tercen.ServiceFactory().taskService.waitDone(task.id) as sci.CubeQueryTask;
    step.model.taskId = task.id;
    // if( removeColumns ){
    //   step.model.columnTable = sci.CrosstabTable()..cellSize = 500..nRows=1;
    // }
    // if( removeRows){
    //   step.model.rowTable = sci.CrosstabTable()..cellSize = 500..nRows=1;
    // }
    
    // // step.model.columnTable = sci.CrosstabTable()..cellSize = 540..nRows=1;
    
    // // step.model.axis.xyAxis.first.yAxis.graphicalFactor = sci.GraphicalFactor()..factor = sci.Factor.json({"name":"measurement", "type":"double"});
    // step.model.axis.xyAxis.first.xAxis.graphicalFactor = sci.GraphicalFactor()..factor = sci.Factor.json({"name":"measurement", "type":"double"});
    // step.model.axis.xyAxis.first.colors = sci.Colors();
    workflow.rev = await tercen.ServiceFactory().workflowService.update(workflow);
    return workflow;
  }

  String getWorkflowState({required sci.Workflow workflow})  {
    """
    NOTE: Only recording errors/exceptions for Data Steps at the moments
    """;
    for( var step in workflow.steps.whereType<sci.DataStep>() ){
      final taskState = step.state.taskState;
      if( taskState is sci.FailedState ){
        return taskState.error == "run.operator.exit.code.137" && taskState.reason.contains("increase memory resources") ?
         "INSUFFICIENT MEMORY" :
         "ERROR";
      }
    }

    return "SUCCESS";
  }

  Future<sci.Relation> _createFakeCrabsData({required String projectId, required String filename, required String owner,
      int nObs = 1000, int nVariable =4, int nSp = 4}) async{
    // sp	sex	index	observation	variable	measurement
    // (character)	(character)	(numeric)	(numeric)	(character)	(numeric)

    //TODO Take into account file path
    // var projObjects =await ProjectDataService().fetchProjectObjects(projectId: projectId);
    // var obj = projObjects.where((obj) => obj.name == filename).firstOrNull;
    // if( obj != null ){
    //   return obj.id;
    // }

    var uniqueSp = <String>[];
    var uniqueVariable = <String>[];
    var uniqueSex = <String>['M', 'F'];

    for( var i = 0; i < nSp; i++){
      uniqueSp.add( StringUtils.getRandomString(3) );
    }
    for( var i = 0; i < nVariable; i++){
      uniqueVariable.add( StringUtils.getRandomString(3) );
    }

    var fileText = "sp,sex,index,observation,variable,measurement\n";
    var index =0;
    for( var oi = 0; oi < nObs; oi++){
      for( var si = 0; si < nSp; si++){
        for( var vi = 0; vi < nVariable; vi++){
          for( var gi = 0; gi < uniqueSex.length; gi++){
            var meas = Random().nextDouble() * 25 * (gi == 0 ? 1-Random().nextDouble()/5 : 1.0); 

            fileText = "$fileText'${uniqueSp[si]}','${uniqueSex[gi]}',${index}.0,${oi}.0,'${uniqueVariable[vi]}',$meas\n";
            index = index + 1;
          }
        }
      }
    }

    var schemaId = await FileDataService().uploadFileAsTable2(projectId: projectId, filename: filename, owner: owner, data: utf8.encode(fileText));
    var sch = await tercen.ServiceFactory().tableSchemaService.get(schemaId);
    
    final colNames = sch.columns.map((col) => col.name).toSet().toList();
    

    //TODO     
    var refRel = sci.SimpleRelation()
      ..id = schemaId;

    var renameRel = sci.RenameRelation.json({
      "id": "rename_${Uuid().v4()}",
      "inNames": colNames,
      "outNames": colNames,
      "relation": refRel.toJson()
    });

    return renameRel;

}

}
