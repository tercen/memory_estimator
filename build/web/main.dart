import 'dart:async';
import 'dart:html' as html;
import 'dart:io';
import 'package:webapp_core/app/app_session.dart';
import 'package:sci_tercen_client/sci_client.dart' as sci;
import 'package:sci_tercen_client/sci_client_service_factory.dart' as tercen;
import 'package:webapp_core/runner/utils/workflow/workflow_settings_utils.dart';
import 'package:webapp_core/runner/workflow_runner.dart';

void main(List<String> arguments) async {
  final estimator = MemoryEstimator();
  await estimator.init();
  // await estimator.init().then((_) => estimator.runEstimation());
  
  // Close browser window after execution completes
  html.window.close();
}

class MemoryEstimator {
  // final Stopwatch totalStopwatch = Stopwatch();
  final Stopwatch partialStopwatch = Stopwatch();
  MemoryEstimator();

  void done(){
    stdout.write( "( ... DONE in ${partialStopwatch.elapsedMilliseconds} ms \n" );
    partialStopwatch.reset();
  }

  void log(String message){
    stdout.write( "[${DateTime.now().toIso8601String()} ] $message" );
   
  }

  Future<void> init() async {
    // totalStopwatch.start();
    partialStopwatch.start();
    final serviceUri = const String.fromEnvironment("TERCEN_URL", defaultValue: "http://127.0.0.1:5400");
    final projectId = const String.fromEnvironment("PROJECT_ID", defaultValue: "b6f4910eac19c2cdb3d318ef0a1fae31");

    final workflowId = "b6f4910eac19c2cdb3d318ef0a1fd0d1";
    final stepId = "ebda5081-aae4-45fc-b91b-f7b4b19d402a";
    log("Initializing memory estimator with:\n\t * Service URL: ${serviceUri}\n\t * Project Id: ${projectId}");

    AppSession appSession = AppSession();
    await appSession.createUserSession();
    done();

    log("Copying workflow to project");
    final runner = WorkflowRunner();
    var workflow = await runner.copyToProject(projectId: projectId, workflowId: workflowId, teamName: "thiago.monteiro", workflowName: "New Workflow name");
    done();
    
    log("Updating ram to 123123123123");
    workflow = WorkflowSettingsUtils.updateEnv(
      workflow: workflow,
      stepId: stepId,
      env: "ram",
      value: "123123123123"
    );
    done();
    
    // await app.init();
    // await AppUser().init();

    // await appData.init(
        // reposJsonPath: "assets/repos.json",
        // stepMapperJsonFile: "assets/workflow_steps.json");
    log("Finished Memory estimator");
  }

//   Future<sci.Workflow> _fetchWorkflow(String workflowId) async {
//     try{
//       return tercen.ServiceFactory().workflowService.get(workflowId);
//     }catch(e){
//       if( e is sci.ServiceError ){
//         Logger().log(level: Logger.ERROR, message: '_fetchWorkflow -- Error fetching workflow: $workflowId ${e.reason}');
//       }
      
//       rethrow;
//     }
    
    
//   }

//   Future<void> runEstimation() async {
// //http://127.0.0.1:5400/thiago.monteiro/w/b6f4910eac19c2cdb3d318ef0a1fd0d1/ds/ebda5081-aae4-45fc-b91b-f7b4b19d402a/crosstab
//     final workflowId = "b6f4910eac19c2cdb3d318ef0a1fd0d1";
//     final stepId = "ebda5081-aae4-45fc-b91b-f7b4b19d402a";
//     var workflow = await _fetchWorkflow(workflowId);
//     final runner = WorkflowRunner();
//     workflow = await runner.doResetStep(null, workflow, stepId: stepId);
//     runner.setStepRam(stepId, 0.5);
//     await runner.doSetup(null, workflow, inPlace: true);
    
//   }
}
