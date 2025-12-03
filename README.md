# Memory Estimator

A command-line tool for estimating memory requirements for Tercen workflows through automated testing with synthetic data.

## Overview

The Memory Estimator performs automated RAM requirement analysis by:
1. Installing an operator from a GitHub repository
2. Reading configuration from `memory_tests.json` in the operator repository
3. Generating and injecting synthetic data with configurable parameters
4. Using hybrid exponential + binary search to find minimum required RAM
5. Optionally running grid searches across multiple parameter combinations
6. Automatically cleaning up all temporary resources (project, workflows, data)

### IMPORTANT NOTE ABOUT WORKFLOW AND PROJECTION

This script will run a workflow named <code>memory_workflow</code> in the operator project.

<code>memory_workflow</code> is a template and must contain a TableStep and a DataStep.

**The input data and projection MUST be based on the Crabs dataset**

### Configuration File Required

Each operator repository **must include** a `memory_tests.json` file at the root directory. This file defines the test parameters for memory estimation. The tool will fail if this file is missing.

## Quick Start

### Install dependencies

```bash
dart pub get
```

### Create memory_tests.json in your operator repository

Add a `memory_tests.json` file at the root of your operator repository:

```json
{
  "data_params": {
    "n_obs": 500,
    "n_sp": 4,
    "n_variable": 4
  },
  "ram_limits": {
    "min_ram_mb": 500,
    "max_ram_mb": 40000,
    "threshold_mb": 500
  },
  "operator_settings": {
    "setting_name": "value"
  }
}
```

All fields are optional. If not specified, defaults or CLI arguments will be used.

### Basic usage

```bash
dart run bin/memory_estimator.dart \
  --repo-url <GITHUB_REPO_URL> \
  --team-name <TEAM_NAME> \
  --username <USERNAME> \
  --password <PASSWORD>
```

This will run memory estimation using the parameters defined in `memory_tests.json` from the operator repository.

## Command-Line Options

**Required:**
- `-r, --repo-url`: GitHub repository URL of the operator to test (e.g., `https://github.com/tercen/mean_operator`)
- `--team-name`: Team name for project and workflow ownership
- `--username`: Tercen username for authentication
- `--password`: Tercen password for authentication

**Optional (override memory_tests.json):**
- `-u, --tercen-url`: Tercen service URL (default: http://127.0.0.1:5400)
- `--repo-version`: Git tag/version to test (optional)
- `--repo-branch`: Git branch to test (default: main)
- `--n-obs`: Number of observations - overrides JSON config (e.g., `500` or `100:5:1000` for range)
- `--n-sp`: Number of species - overrides JSON config
- `--n-variable`: Number of variables - overrides JSON config
- `--min-ram`: Minimum RAM to test in MB - overrides JSON config
- `--max-ram`: Maximum RAM to test in MB - overrides JSON config
- `--threshold`: Stop threshold in MB - overrides JSON config
- `-o, --output`: Output file path to save results as CSV (especially useful for grid search)
- `--setting.NAME=VALUE`: Set operator setting - overrides JSON config (e.g., `--setting.k_neighbors=5` or `--setting.k_neighbors=5:3:15` for range)

**Configuration Precedence:** CLI arguments > memory_tests.json > Defaults

**Range Format:** Use `min:n_steps:max` to define intervals:
- `min`: Starting value (inclusive)
- `n_steps`: Total number of evenly-spaced values to test (must be ≥ 1)
- `max`: Ending value (inclusive)

When multiple range parameters are specified, the tool performs a **grid search** over all combinations. For example, `--n-obs=100:3:500 --setting.k=5:2:10` tests 3×2=6 combinations:
- n_obs=100, k=5
- n_obs=100, k=10
- n_obs=300, k=5
- n_obs=300, k=10
- n_obs=500, k=5
- n_obs=500, k=10

## memory_tests.json Configuration

The `memory_tests.json` file must be placed at the root of your operator repository. This file defines the default test configuration.

### JSON Schema

```json
{
  "data_params": {
    "n_obs": <number or "min:steps:max" string>,
    "n_sp": <number or "min:steps:max" string>,
    "n_variable": <number or "min:steps:max" string>
  },
  "ram_limits": {
    "min_ram_mb": <number>,
    "max_ram_mb": <number>,
    "threshold_mb": <number>
  },
  "operator_settings": {
    "<setting_name>": <value or "min:steps:max" string>,
    ...
  }
}
```

### Example Configurations

**Simple single test:**
```json
{
  "data_params": {
    "n_obs": 1000,
    "n_sp": 4,
    "n_variable": 5
  },
  "ram_limits": {
    "min_ram_mb": 500,
    "max_ram_mb": 8000,
    "threshold_mb": 250
  }
}
```

**Grid search with ranges:**
```json
{
  "data_params": {
    "n_obs": "100:5:1000",
    "n_sp": 4,
    "n_variable": 4
  },
  "operator_settings": {
    "k_neighbors": "5:3:15",
    "metric": "euclidean"
  }
}
```

This will test 5 observation counts (100, 325, 550, 775, 1000) × 3 k values (5, 10, 15) = 15 combinations.

**Enumeration settings (testing multiple values):**
```json
{
  "data_params": {
    "n_obs": 500,
    "n_sp": 4,
    "n_variable": 4
  },
  "operator_settings": {
    "plot_type": "*",
    "theme": "light,dark,minimal"
  }
}
```

For enumeration properties defined in `operator.json`:
- Use `"*"` to test **all** possible values (e.g., all plot types: png, pdf, svg, svg2)
- Use comma-separated values to test a **subset** (e.g., "light,dark,minimal")
- Use a single value for a **fixed** setting (e.g., "png")
- Values are automatically validated against the operator's enum definitions

**Notes:**
- All fields are optional
- Values can be overridden via CLI arguments
- Range syntax for numeric values: `"min:n_steps:max"` where n_steps is the total number of values to test
- Operator settings can mix fixed values, numeric ranges, and enumeration values
- Enumeration values are read from the operator's `operator.json` file

## Usage Examples

### Single Run Using JSON Configuration

```bash
dart run bin/memory_estimator.dart \
  --repo-url https://github.com/tercen/mean_operator \
  --team-name my_team \
  --username myuser \
  --password mypass
```

This uses all parameters from the operator's `memory_tests.json` file.

### Single Run with CLI Override

Override specific JSON values via CLI:

```bash
dart run bin/memory_estimator.dart \
  --repo-url https://github.com/tercen/pca_operator \
  --team-name my_team \
  --username myuser \
  --password mypass \
  --n-obs 1000 \
  --setting.n_components 10
```

This uses JSON config but overrides `n_obs` and the `n_components` setting.

### Grid Search from JSON Configuration

If your `memory_tests.json` contains ranges:

```json
{
  "data_params": {
    "n_obs": "100:5:1000"
  },
  "operator_settings": {
    "k_neighbors": "5:3:15"
  }
}
```

Run with:

```bash
dart run bin/memory_estimator.dart \
  --repo-url https://github.com/tercen/knn_operator \
  --team-name my_team \
  --username myuser \
  --password mypass \
  --output results.csv
```

This will test 15 combinations (5 n-obs values × 3 k_neighbors values) and save results to CSV.

### Grid Search with CLI Override

Override JSON ranges via CLI:

```bash
dart run bin/memory_estimator.dart \
  --repo-url https://github.com/tercen/knn_operator \
  --team-name my_team \
  --username myuser \
  --password mypass \
  --n-obs 200:3:800 \
  --output results.csv
```

### Testing Enumeration Settings

If your `memory_tests.json` contains:
```json
{
  "operator_settings": {
    "plot_type": "*",
    "theme": "light,dark"
  }
}
```

Run with:
```bash
dart run bin/memory_estimator.dart \
  --repo-url https://github.com/tercen/plot_operator \
  --team-name my_team \
  --username myuser \
  --password mypass \
  --output plot_tests.csv
```

This will test all plot_type values (png, pdf, svg, svg2) × 2 theme values (light, dark) = 8 combinations.

### Grid Search with Multiple Operator Settings

```bash
dart run bin/memory_estimator.dart \
  --repo-url https://github.com/tercen/clustering_operator \
  --team-name my_team \
  --username myuser \
  --password mypass \
  --n-obs 100:3:500 \
  --n-sp 2:3:8 \
  --setting.n_clusters 3:3:9 \
  --setting.method kmeans \
  --output memory_profile.csv
```

## How It Works

### Two-Phase Search Algorithm

**Phase 1: Exponential Search**
- Starts from minimum RAM (default 500 MB)
- Increases RAM by 50% each iteration
- Quickly finds an upper bound where the workflow succeeds

**Phase 2: Binary Search**
- Uses the bounds from Phase 1
- Performs binary search to find precise minimum
- Stops when the range is smaller than threshold (default 500 MB)

### Grid Search Mode

When range parameters are specified (using `min:n:max` syntax), the tool:
1. Generates all combinations of parameters
2. Runs memory estimation for each combination
3. Outputs results as CSV with all parameter values and estimated RAM

### Automatic Cleanup

After each run, the tool automatically deletes:
- Test project (including all workflows and data)
- Synthetic data tables
- Temporary files created during execution

The cleanup happens in a `finally` block, ensuring resources are removed even if the estimation fails.

## Output Format

### Single Run Output

```
[2025-01-15T10:30:00.000Z] Initializing memory estimator
[2025-01-15T10:30:00.100Z] Connected to Tercen 1.0.0
[2025-01-15T10:30:00.200Z] User: my_team
[2025-01-15T10:30:00.300Z] Starting RAM estimation for:
  Workflow ID: <auto-generated>
  Step ID: <auto-detected>
  Synthetic data: nObs=500, nSp=4, nVariable=4
[2025-01-15T10:30:05.000Z] Phase 1: Exponential search to find upper bound...
  Testing with 500.00 MB...
  → Insufficient memory, increasing exponentially...
  Testing with 750.00 MB...
  → Success! Found upper bound.
[2025-01-15T10:30:15.000Z] Phase 2: Binary search for precise minimum...
  Range: 500.00 MB - 750.00 MB
  Testing with 625.00 MB...
  → Success! Decreasing RAM to find minimum...
  Converged! Delta: 62.50 MB < 500 MB
[2025-01-15T10:30:25.000Z] ═══════════════════════════════════════
[2025-01-15T10:30:25.000Z] RESULT: Estimated RAM needed: 625.00 MB
[2025-01-15T10:30:25.000Z] RESULT: Runtime: 5.23 seconds
[2025-01-15T10:30:25.000Z] ═══════════════════════════════════════
[2025-01-15T10:30:26.000Z] Cleaning up temporary resources...
  Deleting copied workflow: <workflow-id>
  Deleting synthetic data: <data-id>
  Cleanup complete
```

### Grid Search Output (CSV)

When using `--output results.csv` with ranges:

```csv
n_obs,n_sp,n_variable,settings.k_neighbors,estimated_ram_mb,runtime_seconds
100,4,4,5,512.50,2.34
100,4,4,10,625.00,3.12
100,4,4,15,750.00,4.56
300,4,4,5,1024.00,8.90
300,4,4,10,1250.00,10.23
300,4,4,15,1500.00,12.45
500,4,4,5,1750.00,15.67
500,4,4,10,2000.00,18.90
500,4,4,15,2250.00,21.34
```

Note:
- Operator settings are prefixed with `settings.` in the CSV output
- `runtime_seconds` shows the execution time of the last successful run at the estimated RAM level

## Range Syntax

Use `min:n_steps:max` to specify parameter ranges:
- `min`: Starting value
- `n_steps`: Number of values to test (including min and max)
- `max`: Ending value

Examples:
- `--n-obs 100:5:1000` → Tests: 100, 325, 550, 775, 1000 (5 values)
- `--setting.k 5:3:15` → Tests: 5, 10, 15 (3 values)
- `--n-sp 2:4:8` → Tests: 2, 4, 6, 8 (4 values)

