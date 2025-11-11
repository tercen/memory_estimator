import 'package:sci_tercen_client/sci_client.dart' as sci;
import 'package:sci_tercen_client/sci_client_service_factory.dart' as tercen;

/// Builds a CubeQuery from a DataStep for creating CubeQueryTask
class CubeQueryBuilder {
  /// Build a CubeQuery from a DataStep
  ///
  /// This extracts the query configuration from a step's model without
  /// requiring an existing taskId.
  ///
  /// Parameters:
  /// - step: The DataStep containing the model to extract query from
  /// - relation: Optional relation to use. If not provided, uses step's computedRelation
  ///
  /// Returns a configured CubeQuery ready to be used in a CubeQueryTask
  static sci.CubeQuery fromDataStep(
    sci.DataStep step, {
    sci.Relation? relation,
  }) {
    final model = step.model;

    // Build the CubeQuery
    final query = sci.CubeQuery();

    // Set the relation (data source)
    query.relation = relation ?? step.computedRelation.copy();

    // Extract column and row factors from the axis
    if (model.axis.xyAxis.isNotEmpty) {
      final xyAxis = model.axis.xyAxis.first;

      // Column factors (y-axis in Tercen)
      // Axis has a single graphicalFactor, not a list
      query.colColumns.clear();
      query.colColumns.add(xyAxis.yAxis.graphicalFactor.factor.copy());

      // Row factors (x-axis in Tercen)
      query.rowColumns.clear();
      query.rowColumns.add(xyAxis.xAxis.graphicalFactor.factor.copy());

      // Axis queries from colors and labels
      query.axisQueries.clear();

      // Add color factors as axis queries
      for (var factor in xyAxis.colors.factors) {
        query.axisQueries.add(
          sci.CubeAxisQuery()
            ..yAxis = factor.copy()
        );
      }

      // Add label factors as axis queries
      for (var factor in xyAxis.labels.factors) {
        query.axisQueries.add(
          sci.CubeAxisQuery()
            ..yAxis = factor.copy()
        );
      }
    }

    // Copy filters
    query.filters = model.filters.copy();

    // Copy operator settings
    query.operatorSettings = model.operatorSettings.copy();

    return query;
  }

  /// Create a complete CubeQueryTask from a DataStep by fetching existing task
  ///
  /// This method fetches the existing CubeQueryTask from the step.model.taskId
  /// to get the correct relation and query structure, then updates the filters
  /// from the current model.
  ///
  /// Parameters:
  /// - step: The DataStep to build the task from
  /// - projectId: The project ID for the task
  /// - owner: The owner of the task
  ///
  /// Returns a CubeQueryTask ready to be created and executed
  static Future<sci.CubeQueryTask> createTaskFromExisting(
    sci.DataStep step, {
    required String projectId,
    required String owner,
  }) async {
    // Fetch the existing task to get the correct query with proper relation
    final existingTask = await tercen.ServiceFactory()
        .taskService
        .get(step.model.taskId) as sci.CubeQueryTask;

    // Update filters from current model
    existingTask.query.filters = step.model.filters;

    // Create new task with the query
    final task = sci.CubeQueryTask()
      ..query = existingTask.query
      ..state = sci.InitState()
      ..projectId = projectId
      ..owner = owner;

    return task;
  }

  /// Create a complete CubeQueryTask from a DataStep
  ///
  /// This is a convenience method that builds both the query and wraps it
  /// in a properly initialized CubeQueryTask.
  ///
  /// Parameters:
  /// - step: The DataStep to build the task from
  /// - projectId: The project ID for the task
  /// - owner: The owner of the task
  /// - relation: Optional custom relation (defaults to step's computedRelation)
  ///
  /// Returns a CubeQueryTask ready to be created and executed
  static sci.CubeQueryTask createTask(
    sci.DataStep step, {
    required String projectId,
    required String owner,
    sci.Relation? relation,
  }) {
    final query = fromDataStep(step, relation: relation);

    final task = sci.CubeQueryTask()
      ..query = query
      ..state = sci.InitState()
      ..projectId = projectId
      ..owner = owner;

    return task;
  }
}
