#!/bin/bash

# Example script to run memory estimation with synthetic data
# This will:
# 1. Copy the workflow to the project
# 2. Generate synthetic data (500 obs, 4 species, 4 variables)
# 3. Inject the data into the workflow
# 4. Run RAM estimation using hybrid exponential+binary search
# 5. Clean up all temporary resources (workflow copy + synthetic data)

dart run bin/memory_estimator_new.dart \
  --tercen-url "http://127.0.0.1:5400" \
  --tercen-token "YOUR_TOKEN_HERE" \
  --project-id "YOUR_PROJECT_ID" \
  --workflow-id "YOUR_WORKFLOW_ID" \
  --step-id "YOUR_STEP_ID" \
  --table-step-id "YOUR_TABLE_STEP_ID" \
  --n-obs 500 \
  --n-sp 4 \
  --n-variable 4 \
  --min-ram 500 \
  --max-ram 40000 \
  --threshold 500

# Optional: specify team name
# --team-name "your-team-name"

# Example with different synthetic data sizes:
# Small dataset:  --n-obs 100 --n-sp 2 --n-variable 2
# Medium dataset: --n-obs 1000 --n-sp 5 --n-variable 5
# Large dataset:  --n-obs 5000 --n-sp 10 --n-variable 10
