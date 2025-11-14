# Docker Usage Guide

## Building the Docker Image

### Build locally
```bash
docker build -t memory_estimator:latest .
```

### Build with a specific webapp_lib branch
```bash
docker build --build-arg WEBAPP_LIB_BRANCH=develop -t memory_estimator:latest .
```

### Build with GitHub PAT (if webapp_lib is private)
```bash
docker build --secret id=github_pat,src=<(echo $GH_PAT) -t memory_estimator:latest .
```

## Running the Container

### Basic usage
```bash
docker run --rm ghcr.io/tercen/memory_estimator:main \
  --tercen-url http://tercen-server:5400 \
  --tercen-token YOUR_TOKEN \
  --project-id PROJECT_ID \
  --workflow-id WORKFLOW_ID \
  --step-id STEP_ID \
  --table-step-id TABLE_STEP_ID
```

### With operator settings
```bash
docker run --rm ghcr.io/tercen/memory_estimator:main \
  --tercen-url http://tercen-server:5400 \
  --tercen-token YOUR_TOKEN \
  --project-id PROJECT_ID \
  --workflow-id WORKFLOW_ID \
  --step-id STEP_ID \
  --table-step-id TABLE_STEP_ID \
  --setting.k_neighbors=5 \
  --setting.alpha=0.1
```

### Grid search with ranges
```bash
docker run --rm ghcr.io/tercen/memory_estimator:main \
  --tercen-url http://tercen-server:5400 \
  --tercen-token YOUR_TOKEN \
  --project-id PROJECT_ID \
  --workflow-id WORKFLOW_ID \
  --step-id STEP_ID \
  --table-step-id TABLE_STEP_ID \
  --n-obs 100:3:500 \
  --setting.k_neighbors=5:3:15
```

### Save output to file (mount a volume)
```bash
docker run --rm -v $(pwd):/output ghcr.io/tercen/memory_estimator:main \
  --tercen-url http://tercen-server:5400 \
  --tercen-token YOUR_TOKEN \
  --project-id PROJECT_ID \
  --workflow-id WORKFLOW_ID \
  --step-id STEP_ID \
  --table-step-id TABLE_STEP_ID \
  --output /output/results.csv
```

## Using in GitHub Actions

The image is automatically built and pushed to GitHub Container Registry on every push to the repository.

### Pull the latest image
```bash
docker pull ghcr.io/tercen/memory_estimator:main
```

### Use in a workflow
```yaml
jobs:
  estimate-memory:
    runs-on: ubuntu-latest
    steps:
      - name: Run memory estimator
        run: |
          docker run --rm \
            ghcr.io/tercen/memory_estimator:main \
            --tercen-url ${{ secrets.TERCEN_URL }} \
            --tercen-token ${{ secrets.TERCEN_TOKEN }} \
            --project-id ${{ inputs.project_id }} \
            --workflow-id ${{ inputs.workflow_id }} \
            --step-id ${{ inputs.step_id }} \
            --table-step-id ${{ inputs.table_step_id }}
```

## Notes

- The container includes the compiled Dart binary and minimal runtime dependencies
- The image supports both public and private `webapp_lib` repositories (via GH_PAT secret)
- All command-line options from the standalone tool are supported
- The container uses ENTRYPOINT, so you can pass arguments directly after the image name
