import 'package:webapp_core/app/app_session.dart';
import 'package:sci_tercen_client/sci_client.dart' as sci;
import 'package:sci_tercen_client/sci_client_service_factory.dart' as tercen;
import 'package:webapp_core/service/library_data_service.dart';
import 'package:webapp_core/service/user_data_service.dart';
import 'package:webapp_core/service/project_data_service.dart';
import 'package:webapp_core/runner/utils/workflow/workflow_config_utils.dart';
import 'package:webapp_core/runner/utils/workflow/workflow_settings_utils.dart';
import 'package:webapp_core/utils/string_utils.dart';

void main(List<String> arguments) async {
  print("=" * 80);
  print("TEST: Setup Operator");
  print("=" * 80);

  final serviceUrl = "http://127.0.0.1:5400";
  final username = "test";
  final password = "test";
  final repoUrl = "https://github.com/tercen/plot_operator";
  final repoBranch = "mem_estimate";
  final teamName = "test";

  // Initialize Tercen session
  print("\n1. Initializing session...");
  AppSession appSession = AppSession();
  await appSession.initSession(
      user: username, passw: password, serviceUrl: serviceUrl);
  print("   ✓ Session initialized");

  // Set up library team
  print("\n2. Setting up library team...");
  try {
    await UserDataService()
        .createTeam(teamName: "memory_test_library", owner: teamName, isLibrary: true);
    print("   ✓ Created library team");
  } catch (e) {
    print("   Note: Library team may already exist - $e");
  }

  // Install operator
  print("\n3. Installing operator from branch '$repoBranch'...");
  final installedProject = await LibraryDataService.installOperator(
      url: repoUrl,
      team: "memory_test_library",
      branch: repoBranch,
      tag: null);
  print("   ✓ Installed to project: ${installedProject.name}");
  print("     Project ID: ${installedProject.id}");

  // SETUP Test Project - following exactly what main script does
  print("\n4. Creating test project...");
  final project = await ProjectDataService().createProject(
      name: "MemoryTest_${StringUtils.getRandomString(4)}", owner: teamName);
  print("   ✓ Created project: ${project.name}");
  print("     Project ID: ${project.id}");

  // Copy template from library
  print("\n5. Copying workflow template from library...");
  var workflow = await WorkflowConfigUtils.copyTemplateFromLibrary(
      templateUrl: repoUrl,
      projectId: project.id,
      user: teamName,
      workflowName: "memory_workflow");
  print("   ✓ Workflow created: ${workflow.name}");
  print("     Workflow ID: ${workflow.id}");

  // Get the step ID
  final stepId = workflow.steps.whereType<sci.DataStep>().first.id;
  print("   ✓ Found DataStep ID: $stepId");

  // Set the operator on the workflow step
  print("\n6. Setting operator on workflow step...");
  print("   Setting operator:");
  print("     URL: $repoUrl");
  print("     Version: latest");
  print("     Step ID: $stepId");

  workflow = await WorkflowSettingsUtils.setOperator(
      workflow: workflow,
      operatorUrl: repoUrl,
      operatorVersion: "latest",
      stepId: stepId);
  print("   ✓ Operator set on workflow");

  // Update workflow
  print("\n7. Updating workflow...");
  workflow.rev = await tercen.ServiceFactory().workflowService.update(workflow);
  print("   ✓ Workflow updated");
  print("     Workflow rev: ${workflow.rev}");

  // Get table step
  final tableStepId = workflow.steps.whereType<sci.TableStep>().first.id;
  print("   ✓ Found TableStep ID: $tableStepId");

  // Summary
  print("\n" + "=" * 80);
  print("SETUP COMPLETE - Summary:");
  print("=" * 80);
  print("Project ID:    ${project.id}");
  print("Project Name:  ${project.name}");
  print("Workflow ID:   ${workflow.id}");
  print("Workflow Name: ${workflow.name}");
  print("Step ID:       $stepId");
  print("Table Step ID: $tableStepId");
  print("Operator:      $repoUrl@latest");
  print("=" * 80);
  print("\nNo cleanup performed - project and workflow remain in Tercen");
}
