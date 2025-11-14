# Use the official Dart image
FROM dart:stable AS build

# Install git for cloning dependencies
RUN apt-get update && \
    apt-get install -y git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Clone the webapp_lib dependency (public repo)
ARG WEBAPP_LIB_BRANCH=main
RUN git clone -b ${WEBAPP_LIB_BRANCH} https://github.com/tercen/webapp_lib.git webapp_lib

# Copy pubspec files first for better caching
COPY pubspec.yaml pubspec.yaml

# Get dependencies
RUN dart pub get

# Copy the rest of the application
COPY . .

# Compile the application
RUN dart compile exe bin/memory_estimator.dart -o bin/memory_estimator

# Build minimal runtime image
FROM debian:bookworm-slim AS runtime

# Install CA certificates for HTTPS connections
RUN apt-get update && \
    apt-get install -y ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy the compiled binary
COPY --from=build /app/bin/memory_estimator /usr/local/bin/memory_estimator

# Set the entrypoint
ENTRYPOINT ["/usr/local/bin/memory_estimator"]
