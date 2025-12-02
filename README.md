## Overview

This template repository provides a standardized foundation for Canario customer websites, implementing automated CI/CD pipelines, containerized deployments, and GitLab-integrated feature flags.

## Template Structure

```
canario-template/
├── .gitlab-ci.yml          # Pipeline configuration (includes CI template)
├── Dockerfile              # Container build instructions
├── server/
│   └── server.js          # Express server with feature flag proxy
├── site/
│   ├── index.html         # Customer website frontend
│   └── styles.css         # Styling with feature flag visual feedback
└── README.md              # This file
```

## Key Features

### ✅ CI/CD Pipeline Integration

-   **Pipeline Template**: References `canario-ci` repository for standardized workflows
-   **Stages**: Build → Test → Push → Deploy
-   **Deployment Modes**: Supports both standard and canary deployments
-   **Automated Testing**: Health checks before deployment

### ✅ Docker Containerization

-   Node.js 20 Alpine-based image
-   Express server serving static files
-   Feature flag API endpoint proxying to GitLab

### ✅ Feature Flags (GitLab Integration)

-   Server-side proxy endpoint (`/flags`) fetching from GitLab API
-   Client-side JavaScript polling for flag states
-   Visual feedback when flags change state
-   No rebuild required for flag changes

### ✅ Deployment Options

-   **Standard Deployment**: Immediate replacement of old version
-   **Canary Deployment**: Gradual rollout (10% → 30% → 60% → 100%)

## Setup Instructions

### Prerequisites

1. **GitLab Runner Configuration**:

    - Go to Settings → CI/CD → Runners
    - Select a runner (VM) for your project
    - The pipeline requires a runner with Docker support

2. **GitLab Project Variables** (configure in CI/CD Settings):

    - `GITLAB_ACCESS_TOKEN`: Personal access token with `api` scope
    - `DEPLOY_MODE`: Set to `"standard"` or `"canary"` (default: `"standard"`)
    - `ROUTE_NAME`: Optional route path (defaults to project name)
    - `WEB_SERVER_IP`: Target deployment server IP
    - `WEB_SERVER_USER`: SSH user for deployment

3. **GitLab Feature Flags**:
    - Create feature flags in your GitLab repository under Deploy → Feature Flags
    - Flags can be toggled without rebuilding containers

### Customizing the Template

1. **Replace Site Content**:

    - Edit `site/index.html` and `site/styles.css` with customer-specific content
    - Maintain the feature flag integration pattern shown in the template

2. **Update Feature Flag Names**:

    - In `site/index.html`, change `FEATURE_FLAG_NAME` constant to match your GitLab flags
    - Add multiple flags as needed

3. **Configure Variables and create Project Access Token**:
    - Only the `GITLAB_ACCESS_TOKEN` variable needs to be defined for every project, rest is optional
    - Add new token in you GitLab repository under Settings → Access Token with "api" enabled
    - Set variables in `.gitlab-ci.yml` or as a GitLab CI/CD variable

### Using This Template

1. **Fork/Copy** this template repository for each customer website
2. **Select a runner** in Settings → CI/CD → Runners
3. **Update** the site content with customer-specific design
4. **Configure** GitLab CI/CD variables and feature flags
5. **Push to main branch** to trigger automated deployment

### Host webpage locally

1. Install dependencies (from the project root):

    npm install express node-fetch

2. Set environment variables in your shell:

    set PROJECT_ID=<your_gitlab_project_id>

    set GITLAB_ACCESS_TOKEN=<your_access_token>

    (Use `export` instead of `set` on macOS/Linux.)

3. Start the server:

    node server/server.js

4. Open `http://localhost:8080` in your browser.

## How It Works

### Pipeline Flow

```
Commit to main
    ↓
[Build] Docker image built with commit SHA tag
    ↓
[Test] Container started, health check performed
    ↓
[Push] Image pushed to GitLab Container Registry
    ↓
[Deploy] SSH to web server, execute deploy.sh
    ↓
Container running with HAProxy routing
```

### Feature Flag Integration

1. Container receives `PROJECT_ID` and `GITLAB_ACCESS_TOKEN` as environment variables
2. Server exposes `/flags` endpoint that proxies GitLab Feature Flags API
3. Frontend JavaScript fetches flag states periodically
4. UI updates instantly when flags are toggled in GitLab (no rebuild needed)

### Deployment Process

-   **Standard**: New container replaces old one immediately after health check
-   **Canary**: Traffic gradually shifted over 4 stages (60 seconds each) before full rollout (this can be modified in the canario-deploy repository)
