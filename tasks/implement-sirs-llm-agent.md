# Implementation Plan: SIRS-based LLM Agent

> This document has been updated to provide a comprehensive, production-ready implementation guide for the SIRS-based LLM agent. It addresses clarity, completeness, technical soundness, and security, establishing a robust project structure and detailing critical operational aspects.

## 1. Project Structure

> A new root directory, `LLM-Agent`, is established to encapsulate the entire project, ensuring a clean, modular, and scalable structure. All subsequent file paths are relative to this new root.

```
LLM-Agent/
├── src/
│   ├── agent/
│   │   ├── core.zig
│   │   ├── cli.zig
│   │   └── http_client.zig
│   └── cli.zig (existing, modified)
├── models/
│   └── agent_belief_model.sirs.l
├── services/
│   └── fastapi_service/
│       ├── main.py
│       └── requirements.txt
├── config/
│   └── settings.yaml (new)
├── tests/
│   ├── unit/
│   ├── integration/
│   └── e2e/
├── scripts/
│   └── setup.sh (new)
├── logs/ (new)
└── README.md (new, placeholder)
```

## 2. Agent Architecture Summary

The agent's architecture is composed of five main components:

1.  **User CLI:** A command-line interface for user interaction.
2.  **Agent Core Logic:** The central orchestrator, written in Zig, that manages the agent's perception-inference-decision-action loop.
3.  **SIRS Engine:** The existing SIRS runtime which executes the probabilistic model to infer user intent and other latent states.
4.  **FastAPI Service:** A Python-based API that acts as a bridge between the Agent Core Logic and the LLM.
5.  **LM Studio (LLM):** An external local server that provides large language model capabilities for generating text responses.

The workflow is as follows: The User CLI captures input and sends it to the Agent Core Logic. The Core Logic uses the SIRS Engine to perform inference on the input. Based on the inference results, it formulates a prompt and sends it to the FastAPI Service, which in turn queries LM Studio. The LLM's response is routed back through the FastAPI service to the Core Logic, which then presents the final answer to the user via the CLI.

## 3. SIRS Concepts to be Used

The agent's reasoning will be powered by a probabilistic model defined in the SIRS language. The following SIRS concepts will be utilized:

-   **`model`**: To define the overall structure of the agent's beliefs (`AgentBeliefs`).
-   **`graphical_node`**:
    -   `observed`: To represent data perceived from the environment, such as the user's query text.
    -   `latent`: To model hidden variables that need to be inferred, such as user intent or key entities in the query.
    -   `parameter`: To represent model parameters that can be learned or updated over time.
-   **`factor`**: To define the probabilistic relationships between observed data and latent variables (e.g., the likelihood of observing certain keywords given a specific intent).
-   **`observe`**: To feed the user's query into an instance of the `AgentBeliefs` model.
-   **`infer`**: To execute the probabilistic inference (e.g., using MCMC) to calculate the posterior distribution of the `latent` variables.
-   **Control Flow (`if`, `match`)**: To implement decision logic within the SIRS script based on the inference results, helping to determine the next action.

## 4. New Files to be Created

> File paths have been updated to reflect the new `LLM-Agent` root directory.

| File Path                                       | Description                                                                                             |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `LLM-Agent/src/agent/core.zig`                  | Contains the main orchestration logic for the agent, managing the interaction between all components.     |
| `LLM-Agent/src/agent/cli.zig`                   | Implements the command-line interface specific to the agent, handling user input and displaying output.   |
| `LLM-Agent/src/agent/http_client.zig`           | A simple HTTP client to communicate with the FastAPI service from the Zig-based Agent Core Logic.         |
| `LLM-Agent/models/agent_belief_model.sirs.l`    | The SIRS probabilistic model definition that encodes the agent's reasoning and belief structure.          |
| `LLM-Agent/services/fastapi_service/main.py`    | The main FastAPI application file, exposing an endpoint to interact with LM Studio.                     |
| `LLM-Agent/services/fastapi_service/requirements.txt` | Lists the Python dependencies (`fastapi`, `uvicorn`, `requests`) for the API service.                   |
| `LLM-Agent/config/settings.yaml`                | Centralized configuration file for environment variables, API endpoints, and other settings.              |
| `LLM-Agent/scripts/setup.sh`                    | A shell script to automate the setup of dependencies and environment.                                     |
| `LLM-Agent/README.md`                           | Project README providing an overview, setup instructions, and usage guide.                                |

## 5. Existing Files to be Modified

> File paths have been updated to reflect the new `LLM-Agent` root directory.

| File Path              | Description of Changes                                                                    |
| ---------------------- | ----------------------------------------------------------------------------------------- |
| `src/cli.zig`          | Add a new command for launching the agent. This command will invoke the logic from `LLM-Agent/src/agent/cli.zig`. |
| `build.zig`            | Add the new `LLM-Agent/src/agent/` directory and its files (`core.zig`, `cli.zig`, `http_client.zig`) to the build process. |

## 6. Project Dependencies

### 6.1. Zig Project Dependencies

-   **HTTP Client:** A Zig library for making HTTP requests will be needed in `LLM-Agent/src/agent/http_client.zig` to communicate with the FastAPI service.
    > Rationale: Explicitly stating the need for a robust HTTP client library is crucial for reliable communication. `zig-gamedev/http` or `oven-sh/zig-http` are potential candidates. The choice should consider performance, ease of use, and active maintenance.

### 6.2. Python Service Dependencies

The `LLM-Agent/services/fastapi_service/requirements.txt` file will include:

-   `fastapi`: For building the API.
-   `uvicorn`: To run the FastAPI application server.
-   `requests`: To make HTTP requests to the LM Studio server.
    > Rationale: These are standard and well-supported libraries for building asynchronous Python web services and making HTTP requests.

### 6.3. External System Dependencies

-   **LM Studio:** The agent requires an instance of LM Studio to be running and serving a compatible large language model. The endpoint for LM Studio will be configurable.
    > Rationale: LM Studio is a critical external dependency. Its availability and correct configuration are paramount for the agent's functionality.

## 7. Environment Variables and Configuration

> Centralized configuration is essential for managing varying settings across environments (development, testing, production) and for securely handling sensitive information like API keys.

-   **`LLM_ENDPOINT`**: The URL of the LM Studio server (e.g., `http://localhost:1234/v1/chat/completions`).
    > Rationale: Decoupling the LLM endpoint from the code allows for easy switching between different LLM providers or local instances without code changes.
-   **`LM_STUDIO_MODEL`**: The specific model to use with LM Studio (e.g., `qwen3 14b`).
    > Rationale: Explicitly specifies which model should be loaded in LM Studio for consistent agent behavior.
-   **`SIRS_MODEL_PATH`**: Path to the compiled SIRS model (e.g., `LLM-Agent/models/agent_belief_model.sirs.l`).
    > Rationale: Allows the SIRS model path to be configured externally, facilitating model updates or A/B testing.
-   **`LOG_LEVEL`**: Defines the minimum severity level for logs (e.g., `INFO`, `DEBUG`, `ERROR`).
    > Rationale: Enables dynamic control over logging verbosity, crucial for debugging in development and maintaining performance in production.
-   **`API_KEY_LM_STUDIO`**: (If LM Studio requires authentication) API key for LM Studio.
    > Rationale: Placeholder for future authentication needs. Even if not currently required, it's good practice to anticipate and plan for secure API key management.

**Configuration Management:**
-   Use `LLM-Agent/config/settings.yaml` for non-sensitive, application-specific configurations.
-   Environment variables should be used for sensitive data (e.g., API keys) and deployment-specific settings.
-   The `scripts/setup.sh` will guide users on setting these environment variables.

## 8. Error Handling and Logging Strategy

> A robust error handling and logging strategy is vital for debugging, monitoring, and maintaining the agent in production.

### 8.1. Error Handling

-   **Zig (Agent Core Logic & HTTP Client):**
    -   Utilize Zig's error return types (`!T`) for explicit error propagation.
    -   Implement `try` and `catch` for structured error handling.
    -   Define custom error types for specific agent failures (e.g., `LLMResponseError`, `SIRSInferenceError`).
    -   Graceful degradation: Where possible, implement fallback mechanisms or default behaviors instead of crashing.
    > Rationale: Zig's error handling promotes explicit and safe error management, preventing unexpected panics. Custom error types improve clarity and allow for targeted handling.
-   **Python (FastAPI Service):**
    -   Use FastAPI's `HTTPException` for API-specific errors, returning appropriate HTTP status codes.
    -   Implement `try-except` blocks for handling external API call failures (e.g., LM Studio unavailability) and data parsing errors.
    -   Define custom exception classes for application-specific errors within the FastAPI service.
    > Rationale: Standardized HTTP error responses improve API usability. Comprehensive exception handling prevents service crashes due to external dependencies or malformed data.

### 8.2. Logging

-   **Centralized Logging:** All components (Zig CLI, Agent Core, FastAPI Service) should log to a centralized location or system (e.g., stdout/stderr, then collected by a log aggregator).
    > Rationale: Centralized logging simplifies monitoring, debugging, and auditing across distributed components.
-   **Logging Levels:**
    -   `DEBUG`: Detailed information, typically only of interest when diagnosing problems.
    -   `INFO`: Confirmation that things are working as expected.
    -   `WARNING`: An indication that something unexpected happened, or indicative of some problem in the near future (e.g., ‘disk space low’). The software is still working as expected.
    -   `ERROR`: Due to a more serious problem, the software has not been able to perform some function.
    -   `CRITICAL`: A serious error, indicating that the program itself may be unable to continue running.
    > Rationale: Standard logging levels allow for filtering and prioritization of log messages based on severity.
-   **Log Format:** Structured logging (e.g., JSON) is preferred for easier parsing and analysis by logging tools. Include timestamps, log level, component name, and relevant context (e.g., user ID, request ID).
    > Rationale: Structured logs are machine-readable, enabling efficient querying, filtering, and analysis in log management systems.
-   **Zig Logging:**
    -   Integrate a suitable Zig logging library (e.g., `silly-logger` or a custom implementation).
    -   Log key events: agent startup/shutdown, user query reception, SIRS inference start/end, LLM request/response, decision outcomes.
-   **Python Logging:**
    -   Use Python's built-in `logging` module.
    -   Configure log handlers (e.g., `StreamHandler` for console, `RotatingFileHandler` for files).
    -   Log FastAPI request/response details, LM Studio API calls, and any data transformations.

## 9. Comprehensive Testing Plan

> A multi-faceted testing strategy ensures the reliability, correctness, and performance of the LLM agent.

### 9.1. Unit Tests

-   **Scope:** Individual functions, modules, and classes.
-   **Components:**
    -   **Zig:** `src/agent/core.zig` (individual logic units), `src/agent/cli.zig` (input parsing, output formatting), `src/agent/http_client.zig` (HTTP request construction, response parsing).
    -   **Python:** `services/fastapi_service/main.py` (individual API endpoints, LM Studio interaction logic).
    -   **SIRS:** Individual SIRS factors, nodes, and small model components.
-   **Frameworks:**
    -   **Zig:** Built-in `test` runner.
    -   **Python:** `pytest`.
    -   **SIRS:** Existing SIRS testing capabilities.
    > Rationale: Unit tests provide fast feedback on code changes and isolate defects to specific components.

### 9.2. Integration Tests

-   **Scope:** Interactions between components.
-   **Scenarios:**
    -   Zig Agent Core communicating with FastAPI service.
    -   FastAPI service successfully querying LM Studio (mocked or test instance).
    -   SIRS Engine correctly processing input from Agent Core and returning inference results.
    -   CLI correctly interacting with Agent Core.
-   **Frameworks:**
    -   **Zig:** Built-in `test` runner with mock HTTP servers.
    -   **Python:** `pytest` with `httpx` for API testing and `unittest.mock` for mocking external services.
    > Rationale: Integration tests verify that different parts of the system work together as expected, catching interface issues.

### 9.3. End-to-End (E2E) Tests

-   **Scope:** Full agent workflow from user input to LLM response.
-   **Scenarios:**
    -   User input via CLI -> Agent Core -> SIRS -> FastAPI -> LM Studio -> FastAPI -> Agent Core -> CLI output.
    -   Testing various user intents and expected LLM responses.
    -   Error path testing (e.g., LM Studio unavailable, invalid SIRS inference).
-   **Tools:**
    -   Scripted CLI interactions (e.g., using shell scripts or Python `subprocess`).
    -   Automated testing frameworks that can orchestrate multiple services (e.g., Docker Compose for setting up test environment).
    > Rationale: E2E tests validate the entire system from a user's perspective, ensuring all components function correctly in a deployed environment.

### 9.4. Performance Testing

-   **Scope:** Latency of LLM calls, SIRS inference time, overall response time.
-   **Tools:** `locust`, `JMeter`, custom scripts.
    > Rationale: Ensures the agent meets performance requirements under expected load.

## 10. Security Best Practices

> Security is paramount, especially when dealing with external APIs and user input.

### 10.1. API Key Management

-   **Environment Variables:** Store API keys (e.g., `API_KEY_LM_STUDIO`) as environment variables, never hardcode them in source code.
    > Rationale: Prevents sensitive credentials from being exposed in version control.
-   **Secrets Management:** For production deployments, utilize a dedicated secrets management solution (e.g., HashiCorp Vault, AWS Secrets Manager, Kubernetes Secrets).
    > Rationale: Provides a secure, centralized, and auditable way to manage and distribute secrets to applications.
-   **Least Privilege:** Ensure that the FastAPI service (or any component interacting with the LLM) only has the necessary permissions to perform its function.
    > Rationale: Minimizes the impact of a potential compromise.

### 10.2. Prompt Injection Mitigation

-   **Input Validation and Sanitization:**
    -   Validate and sanitize all user inputs before they are incorporated into LLM prompts. Remove or escape special characters that could alter prompt intent.
    -   Use allow-lists for expected input formats where possible.
    > Rationale: Reduces the attack surface by ensuring only legitimate input reaches the LLM.
-   **Clear Delimiters:** Use clear and unambiguous delimiters (e.g., `###`, `---`) to separate user input from system instructions within the prompt.
    > Rationale: Helps the LLM distinguish between instructions and user-provided text, making it harder for attackers to "break out" of the intended prompt.
-   **Principle of Least Privilege for LLM:** Design prompts so the LLM has minimal "agency" or ability to perform actions beyond its intended scope. Avoid giving the LLM direct access to sensitive functions or data.
    > Rationale: Limits the potential damage if a prompt injection attack is successful.
-   **Human Review/Approval (if applicable):** For critical actions, consider a human review or approval step before the LLM's output is acted upon.
    > Rationale: Adds an extra layer of security for high-impact operations.
-   **Regular Updates:** Keep all libraries, frameworks, and the LLM itself updated to patch known vulnerabilities.
    > Rationale: Ensures protection against newly discovered exploits.

## 11. Deployment Considerations

> Planning for deployment ensures the agent can be reliably run in various environments.

-   **Containerization (Docker):**
    -   Create `Dockerfile`s for the FastAPI service and potentially the Zig agent (if complex dependencies).
    -   Use `docker-compose.yaml` for local development and orchestration of both services and LM Studio.
    > Rationale: Containerization provides consistent environments, simplifies dependency management, and improves portability.
-   **Orchestration:** For production, consider Kubernetes or similar orchestration platforms for scalability, high availability, and automated deployments.
-   **CI/CD Pipeline:** Implement a CI/CD pipeline to automate testing, building, and deployment processes.
    > Rationale: Automates the software delivery lifecycle, reducing manual errors and accelerating releases.

## 12. Setup and Installation Guide

> A clear setup guide is crucial for developers and users to get the agent running.

### 12.1. Prerequisites

-   **Zig Compiler:** Install Zig (version X.Y.Z, specify exact version).
-   **Python:** Install Python 3.x.x.
-   **LM Studio:** Download and install LM Studio. Ensure a compatible LLM model is downloaded and served.
-   **Git:** For cloning the repository.

### 12.2. Installation Steps

1.  **Clone the Repository:**
    ```bash
    git clone https://github.com/your-org/LLM-Agent.git
    cd LLM-Agent
    ```
2.  **Set up Environment Variables:**
    > Rationale: Emphasizes the importance of environment variables for configuration and security.
    Create a `.env` file or set them directly in your shell:
    ```bash
    export LLM_ENDPOINT="http://localhost:1234/v1/chat/completions"
    export LM_STUDIO_MODEL="qwen3 14b"
    export SIRS_MODEL_PATH="./models/agent_belief_model.sirs.l"
    export LOG_LEVEL="INFO"
    # export API_KEY_LM_STUDIO="your_lm_studio_api_key_if_needed"
    ```
    > Note: For production, use a dedicated secrets management solution.
3.  **Install Python Dependencies:**
    ```bash
    cd services/fastapi_service
    pip install -r requirements.txt
    cd ../..
    ```
4.  **Build Zig Agent:**
    ```bash
    zig build
    ```
    > Rationale: Standard Zig build command.
5.  **Run LM Studio:**
    Start LM Studio and load the model specified by `LM_STUDIO_MODEL` (qwen3 14b), ensuring it's serving on the configured `LLM_ENDPOINT`.
6.  **Run FastAPI Service:**
    ```bash
    uvicorn services.fastapi_service.main:app --host 0.0.0.0 --port 8000
    ```
    > Rationale: Standard command to run a FastAPI application with Uvicorn.
7.  **Run LLM Agent CLI:**
    ```bash
    zig build run-agent-cli # Assuming 'run-agent-cli' is the new command in build.zig
    ```
    > Rationale: This command will be added to `build.zig` to launch the agent's CLI.

## 13. Future Enhancements

-   **Advanced SIRS Models:** Explore more complex probabilistic models for richer inference.
-   **Tool Use/Function Calling:** Integrate the LLM's ability to call external tools or functions based on inferred intent.
-   **Memory Management:** Implement a more sophisticated memory system for the agent to retain conversational context.
-   **Fine-tuning LLM:** Investigate fine-tuning smaller LLMs for specific agent tasks.
-   **Observability:** Integrate with monitoring and tracing tools (e.g., Prometheus, Grafana, OpenTelemetry).
-   **Scalability:** Explore distributed SIRS inference or LLM load balancing.