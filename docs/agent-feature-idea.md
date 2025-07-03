# Agent Feature Idea: SIRS-based LLM Agent with FastAPI and CLI

## 1. Introduction

This document outlines the initial idea for an intelligent agent leveraging the SIRS language for probabilistic modeling and inference, integrated with LM Studio via FastAPI, and accessible through a simple command-line interface (CLI). The agent will operate based on a continuous perception-inference-decision-action loop, enabling it to reason under uncertainty and respond to user queries.

## 2. Conceptual Agentic Workflow Loop (SIRS-based)

The agent will follow a conceptual workflow loop, with each step utilizing SIRS capabilities as described in `docs/finding.md`:

### 2.1. Perceive: Data Ingestion

*   **Description:** The agent receives new data from its environment. In this context, the primary input will be user questions posed via the CLI.
*   **SIRS Relevance:** This corresponds to the `observed` graphical nodes in the SIRS model, where external data conditions the agent's beliefs.
*   **Implementation Idea:** The CLI will capture user input, which will then be passed to the agent's core logic.

### 2.2. Model/Infer: Belief Update and Inference

*   **Description:** The agent uses its SIRS probabilistic model to update its beliefs about the environment and its own state, performing inference on latent variables and parameters. This involves understanding the user's intent, extracting relevant entities, and inferring potential answers or actions.
*   **SIRS Relevance:** This is the core of the SIRS application, utilizing `infer` expressions on `latent` and `parameter` graphical nodes, governed by `factor` relationships.
*   **Implementation Idea:**
    *   Define a SIRS model (`model AgentBeliefs { ... }`) that represents the agent's knowledge base, including observed inputs (user query), latent variables (user intent, relevant concepts), and parameters (e.g., confidence levels).
    *   Use `observe` statements to incorporate the user's question into the SIRS model.
    *   Execute `infer` to derive probabilistic insights (e.g., the most likely interpretation of the user's question, or the probability distribution over possible answers).

### 2.3. Decide: Action Determination

*   **Description:** Based on the inferred beliefs (e.g., the most likely state, or the posterior distribution of a critical variable), the agent's internal logic determines a course of action. This could involve formulating a response, querying an external knowledge base, or triggering another process.
*   **SIRS Relevance:** While SIRS itself doesn't directly "decide," its inference results (`inferred_state`) provide the necessary input for decision-making logic implemented using SIRS's `if` or `match` control flow statements.
*   **Implementation Idea:**
    *   Analyze the output of the SIRS `infer` step.
    *   Implement SIRS logic (e.g., `if (most_likely_intent == "query_knowledge_base") { ... }`) to map inferred beliefs to specific actions or response generation strategies.

### 2.4. Act (External): Output and Integration

*   **Description:** The SIRS program outputs a decision or a command that an external system or another part of the agent's architecture can execute. This part typically involves integration with external APIs or systems, specifically LM Studio for generating responses.
*   **SIRS Relevance:** This step involves the agent interacting with the external environment, which in SIRS could be conceptualized as the "effect" of the model's output.
*   **Implementation Idea:**
    *   **FastAPI Integration:** Create a FastAPI application that exposes an endpoint for the agent to send prompts to LM Studio and receive generated text.
    *   The SIRS decision logic will formulate a prompt based on inferred beliefs and send it to the FastAPI service.
    *   The FastAPI service will then communicate with LM Studio to get the LLM's response.
    *   The LLM's response will be returned to the agent's core logic.

### 2.5. Repeat: Continuous Learning

*   **Description:** The cycle continues as new observations (subsequent user inputs, feedback) become available, allowing the agent to adapt and learn over time.
*   **SIRS Relevance:** The iterative nature of the loop allows for continuous updates to the SIRS model's parameters and beliefs as more data is observed.
*   **Implementation Idea:** The CLI will facilitate this continuous interaction, allowing users to pose follow-up questions or provide feedback, which then re-initiates the perception-inference-decision-action loop.

## 3. Technical Stack

*   **Core Logic:** SIRS Language for probabilistic modeling and inference.
*   **LLM Integration:** LM Studio (local LLM server).
*   **API Layer:** FastAPI for communication between the agent and LM Studio.
*   **User Interface:** Simple Command Line Interface (CLI).

## 4. Initial Development Steps

1.  **Set up LM Studio:** Ensure LM Studio is running and serving a compatible LLM.
2.  **FastAPI Service:** Develop a basic FastAPI application to interact with LM Studio.
3.  **SIRS Model Definition:** Begin defining a simple SIRS probabilistic model for a specific use case (e.g., intent recognition, simple Q&A).
4.  **CLI Development:** Create a basic CLI that takes user input and initiates the agentic workflow.
5.  **Integration:** Connect the CLI, SIRS inference, and FastAPI/LM Studio components to form the complete loop.