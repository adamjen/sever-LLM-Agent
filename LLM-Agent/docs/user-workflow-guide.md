# User Workflow Guide

This document details end-to-end user interaction scenarios with the LLM Agent.

## 1. CLI Command Reference

This section provides a reference for all available Command Line Interface (CLI) commands.

- `agent start`: Initializes and starts the LLM agent's background services, including the FastAPI endpoint for API interactions. This command makes the agent ready to receive queries.
- `agent stop`: Gracefully shuts down all running agent processes. This should be used to ensure a clean exit.
- `agent status`: Reports the current operational status of the agent (e.g., `running`, `stopped`, `error`). It's useful for diagnosing connectivity issues.
- `agent query "<your query>"`: Sends a single, self-contained query directly to the agent. The agent's response is printed to the standard output. This is ideal for quick, non-conversational interactions.

## 2. Session Management Flow

This section describes the lifecycle of a user session, which is designed to support coherent, multi-turn conversations.

- **Initiation:** A new session is automatically created when a user sends their first query to the agent. A unique `session_id` is generated and associated with all subsequent interactions.
- **Context Handling:** The agent maintains the conversational context (previous questions and answers) within the active session. This allows users to ask follow-up questions and have the agent understand the broader conversation.
- **Timeout:** To manage resources, a session will automatically time out and be closed after a configurable period of user inactivity. The default timeout is 30 minutes.
- **Termination:** A session can be explicitly terminated by the user. This clears the conversation history and allows for a fresh start.

## 3. Error Recovery Procedures

This section provides guidance on troubleshooting and recovering from common errors.

- **Invalid Query:** If a query is malformed or uses incorrect syntax, the agent will return a specific error message. Review the query for typos or structural errors and resubmit.
- **Agent Not Responding:** If the agent fails to respond, first use `agent status` to check if the service is running. If it is stopped, use `agent start` to restart it. If it is running but unresponsive, check the agent's logs for error messages.
- **Unexpected Output:** If the agent's response is nonsensical or irrelevant, it may be due to ambiguous context. Try rephrasing the question for more clarity. If the issue persists, terminating the session and starting a new one can resolve context-related confusion.
- **Inconsistent or Biased Output:** If you notice the agent providing factually inconsistent or biased responses, please report this. You can start a new session to reset the agent's context.

## 4. Multi-turn Conversation Examples

This section provides examples of multi-turn conversations with the agent.

**Example 1: Simple Q&A**

> **User:** What is the capital of France?
> **Agent:** The capital of France is Paris.

**Example 2: Follow-up Question**

> **User:** What is the capital of France?
> **Agent:** The capital of France is Paris.
> **User:** What is its population?
> **Agent:** The population of Paris is approximately 2.141 million people.

**Example 3: Context-Switching and Clarification**

> **User:** Can you recommend a good book on astrophysics?
> **Agent:** "A Brief History of Time" by Stephen Hawking is a highly recommended book on the subject.
> **User:** What about for beginners?
> **Agent:** For beginners, "Astrophysics for People in a Hurry" by Neil deGrasse Tyson is an excellent and accessible choice.
> **User:** Thanks. Now, can you tell me the weather in London?
> **Agent:** The current weather in London is partly cloudy with a temperature of 15°C.