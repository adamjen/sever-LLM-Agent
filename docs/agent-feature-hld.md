# High-Level Design: SIRS-based LLM Agent with FastAPI and CLI

## 1. Introduction

This High-Level Design (HLD) document details the architectural overview of the proposed intelligent agent. It expands upon the initial idea outlined in `docs/agent-feature-idea.md`, providing a more structured view of the system's components, their interactions, and the overall data flow. The agent will leverage the SIRS language for probabilistic modeling, integrate with LM Studio via FastAPI, and offer a command-line interface for user interaction.

## 2. System Architecture Overview

The agent's architecture is composed of several interconnected components, forming a continuous loop of perception, inference, decision, and action.

```mermaid
graph TD
    A[User CLI] --> B{Agent Core Logic};
    B --> C[SIRS Engine];
    C --> B;
    B --> D[FastAPI Service];
    D --> E[LM Studio (LLM)];
    E --> D;
    D --> B;
```

**Components:**

*   **User CLI:** The primary interface for users to interact with the agent, posing questions and receiving responses.
*   **Agent Core Logic:** The central orchestrator of the agent's workflow. It manages the perception-inference-decision-action loop, coordinates between the SIRS Engine and FastAPI Service, and processes inputs/outputs.
*   **SIRS Engine:** Responsible for executing SIRS probabilistic models. It performs inference on observed data to update the agent's beliefs and derive insights (e.g., user intent, relevant context).
*   **FastAPI Service:** An intermediary API layer that handles communication with external services, specifically LM Studio. It receives requests from the Agent Core Logic, forwards them to LM Studio, and returns the LLM's responses.
*   **LM Studio (LLM):** A local large language model server that provides the generative AI capabilities for the agent, producing human-like text responses based on prompts.

## 3. Component Breakdown and Responsibilities

### 3.1. User CLI

*   **Responsibility:**
    *   Accept user input (questions).
    *   Display agent responses.
    *   Manage the interactive command-line session.
*   **Key Interactions:** Communicates directly with the Agent Core Logic.

### 3.2. Agent Core Logic

*   **Responsibility:**
    *   **Perception:** Receives user input from the CLI.
    *   **Orchestration:** Manages the flow of data and control through the SIRS Engine and FastAPI Service.
    *   **Decision Making:** Interprets the results from the SIRS Engine to formulate actions or prompts for the LLM.
    *   **Response Generation:** Processes LLM output and prepares it for display via the CLI.
*   **Key Interactions:**
    *   Sends observed data to the SIRS Engine for inference.
    *   Sends prompts (derived from SIRS inference) to the FastAPI Service for LLM interaction.
    *   Receives inferred beliefs from the SIRS Engine.
    *   Receives LLM responses from the FastAPI Service.

### 3.3. SIRS Engine

*   **Responsibility:**
    *   Host and execute the agent's probabilistic model defined in SIRS language.
    *   Perform `observe` operations to incorporate new data.
    *   Execute `infer` operations to update beliefs about latent variables and parameters.
    *   Provide inferred results (e.g., posterior distributions, most likely states) to the Agent Core Logic.
*   **Key Interactions:** Receives data and inference requests from the Agent Core Logic, returns inference results.

### 3.4. FastAPI Service

*   **Responsibility:**
    *   Expose a RESTful API endpoint for LLM interaction.
    *   Receive prompts from the Agent Core Logic.
    *   Forward prompts to the LM Studio server.
    *   Receive generated text from LM Studio.
    *   Return LLM responses to the Agent Core Logic.
    *   Handle potential errors and timeouts during communication with LM Studio.
*   **Key Interactions:**
    *   Receives HTTP requests from the Agent Core Logic.
    *   Makes HTTP requests to the LM Studio API.

### 3.5. LM Studio (LLM)

*   **Responsibility:**
    *   Serve a pre-loaded Large Language Model.
    *   Generate text responses based on input prompts.
*   **Key Interactions:** Receives HTTP requests from the FastAPI Service, returns generated text.

## 4. Data Flow

1.  **User Input:** User types a question into the CLI.
2.  **Perception (CLI -> Agent Core):** The CLI captures the input and sends it to the Agent Core Logic.
3.  **Observation (Agent Core -> SIRS Engine):** The Agent Core Logic translates the user input into an observation for the SIRS model and sends it to the SIRS Engine.
4.  **Inference (SIRS Engine):** The SIRS Engine updates its probabilistic model based on the observation and performs inference to determine user intent, extract entities, or infer relevant context.
5.  **Inferred Beliefs (SIRS Engine -> Agent Core):** The SIRS Engine returns the inferred beliefs (e.g., the most probable intent, relevant parameters) to the Agent Core Logic.
6.  **Decision (Agent Core):** The Agent Core Logic uses the inferred beliefs to formulate a precise prompt for the LLM.
7.  **Action Request (Agent Core -> FastAPI Service):** The Agent Core Logic sends the LLM prompt to the FastAPI Service.
8.  **LLM Request (FastAPI Service -> LM Studio):** The FastAPI Service forwards the prompt to LM Studio.
9.  **LLM Response (LM Studio -> FastAPI Service):** LM Studio processes the prompt and returns the generated text response to the FastAPI Service.
10. **Response Delivery (FastAPI Service -> Agent Core):** The FastAPI Service sends the LLM's response back to the Agent Core Logic.
11. **Output (Agent Core -> CLI):** The Agent Core Logic formats the LLM's response and sends it to the CLI for display to the user.
12. **Repeat:** The system awaits new user input, continuing the loop.

## 5. High-Level Design Considerations

*   **Scalability:**
    *   **LM Studio:** Running LM Studio locally might limit scalability for multiple concurrent users. For production, consider cloud-based LLM APIs or dedicated GPU instances.
    *   **FastAPI:** FastAPI is highly performant and can handle multiple concurrent requests.
*   **Error Handling:**
    *   Implement robust error handling in the FastAPI Service for LM Studio communication (e.g., connection errors, timeouts, invalid responses).
    *   The Agent Core Logic should gracefully handle errors from both the SIRS Engine and the FastAPI Service, providing informative feedback to the user.
*   **Security:**
    *   For local deployment, security concerns are minimal. For external exposure, secure FastAPI endpoints with authentication/authorization.
    *   Ensure LM Studio is configured securely if exposed to a network.
*   **Performance:**
    *   Optimize SIRS models for efficient inference.
    *   Monitor latency between components, especially LM Studio response times.
*   **Modularity:**
    *   Each component (CLI, Agent Core, SIRS Engine, FastAPI Service) should be developed as a distinct module or service to promote maintainability and independent evolution.
*   **Configuration:**
    *   Externalize configurations (e.g., LM Studio endpoint, SIRS model paths) to allow easy deployment and modification without code changes.
*   **Observability:**
    *   Implement logging for each component to aid in debugging and monitoring the agent's behavior.
    *   Consider metrics for tracking inference times, LLM response times, and overall workflow duration.