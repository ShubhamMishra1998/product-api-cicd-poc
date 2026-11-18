# Product API CI/CD Proof of Concept

A small Spring Boot REST API used to demonstrate automated testing, Docker image publishing, and blue-green deployment to a local Windows machine. The application uses an in-memory repository; this project is a learning/proof-of-concept setup, not a production-ready service.

## Technology

- Java 21 and Spring Boot 4.1.2
- Maven, using the checked-in Maven Wrapper
- Spring MVC and Jakarta Bean Validation
- JUnit 5, Mockito, and Spring MockMvc
- Docker, Docker Compose, Nginx
- GitHub Actions and GitHub Container Registry (GHCR)
- Rancher Desktop on a self-hosted Windows runner

## Application

Requests flow through the controller, service, and repository:

```text
HTTP request → ProductController → ProductService → ProductRepository
HTTP response ← ProductResponse ← ProductService
```

- `ProductController` exposes the REST endpoints.
- `ProductService` implements product operations and maps stored products to response DTOs.
- `ProductRepository` stores products in a `ConcurrentHashMap` and assigns IDs with an `AtomicLong`.
- `CreateProductRequest` validates incoming data; `ProductResponse` defines the response shape.
- `GlobalExceptionHandler` maps validation errors to HTTP 400 and missing products to HTTP 404.

### API

The application listens on port `8080` by default.

| Method | Path | Description | Success response |
|---|---|---|---|
| `POST` | `/api/products` | Create a product | `201 Created` |
| `GET` | `/api/products` | List products | `200 OK` |
| `GET` | `/api/products/{id}` | Get a product | `200 OK` |
| `DELETE` | `/api/products/{id}` | Delete a product | `204 No Content` |

Example request:

```json
{
  "name": "Monitor",
  "description": "4K Monitor",
  "price": 25000.00
}
```

The name is required, cannot be blank, and is limited to 100 characters. The description is optional and limited to 500 characters. The price is required and must be at least `0.01`.

Spring Boot Actuator exposes `/actuator/health` and `/actuator/info`. Health details are hidden; the health endpoint reports the overall status used by the deployment checks.

### Data and limitations

Products are held only in each application process's memory. There is no database or shared storage:

- Data is lost when a container is recreated or the application restarts.
- Blue and green instances have independent data and ID counters. Switching traffic can therefore make previously created products disappear or show different results.
- Product list ordering is not guaranteed.

## Run and test locally

Requirements: Java 21. The Maven Wrapper downloads and runs the configured Maven distribution.

On Windows PowerShell:

```powershell
.\mvnw.cmd spring-boot:run
```

The API is then available at `http://localhost:8080`. To run the tests and full Maven verification:

```powershell
.\mvnw.cmd clean verify
```

On Linux/macOS, use `./mvnw` instead.

Tests currently cover:

- Spring application context startup.
- Six service-level behaviors with a mocked repository.
- Three MVC integration scenarios using MockMvc: product creation, missing-product handling, and invalid input.

The creation integration test checks the creation response; despite its method name, it does not issue a follow-up GET request.

## CI/CD overview

The main workflow is `.github/workflows/ci.yml`. Its flow is:

```text
Push to main / pull request to main / manual dispatch
                         │
                         ▼
             Build and test on GitHub-hosted Ubuntu
                         │
                         ▼
       Publish image to GHCR (eligible main-branch runs)
                         │
                         ▼
       Deploy on the self-hosted Windows Rancher runner
```

### Triggers and gates

The workflow runs on pushes to `main`, pull requests targeting `main`, and manual `workflow_dispatch` runs.

1. **Build and test:** Runs on `ubuntu-latest`, checks out the source, configures Temurin Java 21 with Maven dependency caching, and runs `./mvnw -B clean verify`. Surefire XML reports are uploaded as `product-api-test-reports` for seven days, even if an earlier step fails.
2. **Publish image:** Depends on successful build and tests. It is skipped for pull requests and unless the ref is `main`. Docker Buildx builds and pushes `ghcr.io/shubhammishra1998/product-api-cicd-poc` to GHCR using the workflow's `GITHUB_TOKEN`. Generated tags include a short-SHA tag, a branch tag, and `latest` for the default branch. The short-SHA image reference is passed to deployment.
3. **Deploy:** Depends on image publication and runs on a self-hosted runner labelled `self-hosted`, `Windows`, `X64`, and `rancher`. It invokes the PowerShell blue-green deployment script and then checks health through Nginx at `http://localhost:8081/actuator/health`.

Pull requests run the build/test job only. Manual dispatch does not by itself guarantee deployment: publication and deployment still require the selected ref to be `main`.

The deploy job targets the GitHub environment `local-deployment`. The workflow YAML does not itself require an approval; configure required reviewers or other protection rules for that environment in GitHub repository settings if deployment must be manually approved.

### Docker image

`Dockerfile` uses two stages:

1. A Maven/Java 21 builder downloads dependencies and packages the application.
2. A Java 21 JRE runtime image receives the packaged JAR and starts it with `java -jar`.

The Docker build uses `-DskipTests`. Tests are gated by the earlier CI job rather than run inside the image build.

## Blue-green deployment

`docker-compose.yml` defines blue and green application containers plus Nginx:

| Service | Container port | Host port |
|---|---:|---:|
| `product-api-blue` | `8080` | `127.0.0.1:8082` |
| `product-api-green` | `8080` | `127.0.0.1:8083` |
| `nginx` | `80` | `8081` |

Clients access the API through Nginx on port `8081`. The deployment script checks the inactive application directly on port `8082` or `8083` before switching Nginx traffic.

### Deployment process

`scripts/deploy-blue-green.ps1` accepts the new image reference from the workflow and:

1. Reads the active slot from `C:\product-api-deployment\active-slot.txt` and chooses the other slot.
2. Pulls the new image and recreates only that inactive Compose service.
3. Retries the target's Actuator health check for up to 30 attempts.
4. Rewrites `C:\product-api-deployment\nginx\nginx.conf` to route to the healthy target.
5. Validates Nginx configuration and reloads Nginx.
6. Writes the new active slot only after the traffic switch succeeds.

The previous application slot is left running. If the target health check fails, the script does not change traffic. If Nginx validation or reload fails, it attempts to restore the previous Nginx configuration.

### Required runner setup

The deployment runner must be online with the labels above and have PowerShell, Docker CLI, Docker Compose, and a working Docker daemon (for example, from Rancher Desktop). It also needs permission to pull the GHCR package; for a private package, configure registry authentication on the runner.

Before the first deployment, prepare the persistent files and running Compose stack expected by the scripts:

- `C:\product-api-deployment\active-slot.txt` must contain exactly `blue` or `green` and must match the currently routed/active slot.
- `C:\product-api-deployment\nginx\nginx.conf` must exist and describe the current Nginx upstream.
- The Compose project and Nginx container must already be running. The deployment script does not initialize them.

Compose mounts the persistent Nginx configuration file from that Windows path. The repository's `nginx/nginx.conf` is an example/configuration source; the deployment script changes the persistent copy on the runner. Similarly, the repository's root `active-slot.txt` is not the state file used by the script.

The Compose file has fixed SHA-tagged defaults for both application slots. The deployment script overrides the image only for the target slot. Do not assume those defaults identify the current release.

### Rollback

Run `scripts/rollback-blue-green.ps1` manually from an appropriately configured PowerShell environment on the deployment machine. It reads the current slot, checks the other slot's health, changes and validates Nginx configuration, reloads Nginx, and updates the active-slot file. It switches to whatever image is still running in the other slot; it does not restore a selected historical image or recover in-memory product data.

The workflow does not automatically call the rollback script if its final health check through Nginx fails.

### Runner diagnostic workflow

`.github/workflows/runner-check.yml` is a separate manually triggered workflow. On the same self-hosted runner labels, it checks runner execution, Docker and Compose versions, daemon availability, and running containers. It does not build, test, or deploy the application.

## Operational scope

This repository demonstrates a CI/CD path to one local Rancher Desktop host. It does not configure a database, persistent product storage, authentication/authorization, TLS, a production hosting platform, deployment concurrency control, or automatic rollback. In particular, the in-memory repository is not suitable for a blue-green deployment where users expect data to survive instance changes.