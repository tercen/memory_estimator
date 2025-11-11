#!/bin/bash

# Example script to run the memory estimator
# Replace PROJECT_ID with your actual project ID

PROJECT_ID="your_project_id_here"
TERCEN_URL="http://127.0.0.1:5400"
TERCEN_TOKEN=""  # Optional: Add your token here if needed

echo "Running Memory Estimator..."
echo "Project ID: $PROJECT_ID"
echo "Tercen URL: $TERCEN_URL"
echo ""

if [ -n "$TERCEN_TOKEN" ]; then
  dart run bin/memory_estimator.dart \
    --project-id "$PROJECT_ID" \
    --tercen-url "$TERCEN_URL" \
    --tercen-token "$TERCEN_TOKEN"
else
  dart run bin/memory_estimator.dart \
    --project-id "$PROJECT_ID" \
    --tercen-url "$TERCEN_URL"
fi
