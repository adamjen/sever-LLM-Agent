# Data Schema Definition

This document formalizes the data structures used across the LLM Agent system.

## 1. SIRS Model Schema

This section defines the input and output schemas for the SIRS probabilistic models.

### 1.1. Input Schema

The SIRS model expects a JSON object containing the data and any prior parameters for the model execution.

```json
{
  "model_name": "string",
  "data": {
    "observations": [ "number" ],
    "covariates": [ "number" ]
  },
  "priors": {
    "mean_mu": "number",
    "mean_sigma": "number",
    "sigma_alpha": "number",
    "sigma_beta": "number"
  }
}
```

-   **model_name**: The name of the SIRS model to be executed. (Required)
-   **data**: An object containing the observational data.
   -   **observations**: An array of numerical observations. Must not be empty.
   -   **covariates**: An array of numerical covariates, corresponding to each observation.
-   **priors**: An object containing the prior distributions for the model parameters.
   -   **mean_mu**: The mean of the prior for the mean parameter.
   -   **mean_sigma**: The standard deviation of the prior for the mean parameter. Must be positive.
   -   **sigma_alpha**: The alpha parameter for the prior of the sigma parameter.
   -   **sigma_beta**: The beta parameter for the prior of the sigma parameter.

### 1.2. Output Schema

The SIRS model outputs a JSON object containing the posterior samples for the monitored variables, along with diagnostic information.

```json
{
  "model_name": "string",
  "posterior_samples": {
    "mean": [ "number" ],
    "sigma": [ "number" ]
  },
  "diagnostics": {
    "r_hat": "number",
    "effective_sample_size": "integer"
  }
}
```

-   **model_name**: The name of the SIRS model that was executed.
-   **posterior_samples**: An object containing the posterior samples for the model parameters.
   -   **mean**: An array of posterior samples for the mean parameter.
   -   **sigma**: An array of posterior samples for the sigma parameter.
-   **diagnostics**: An object containing diagnostic information about the MCMC simulation.
   -   **r_hat**: The Gelman-Rubin convergence diagnostic. A value close to 1.0 indicates convergence.
   -   **effective_sample_size**: The effective sample size of the posterior samples, which measures the number of independent samples.

## 2. LLM Prompt/Response Schema

This section defines the schema for data exchanged with the Large Language Model.

### 2.1. Prompt Schema
 
 ```json
 {
   "session_id": "string",
   "context": "string",
   "prompt": "string"
 }
 ```
 
-   **session_id**: A unique identifier for the user session. Recommended format is UUID v4.
    -   *Example*: `"f81d4fae-7dec-11d0-a765-00a0c91e6bf6"`
-   **context**: A string containing the history of the conversation or other relevant data to provide context for the prompt.
 
 ### 2.2. Response Schema
 
 ```json
 {
   "session_id": "string",
   "response_text": "string",
   "confidence_score": "number"
 }
 ```
-   **confidence_score**: A numerical value between 0.0 and 1.0 indicating the model's confidence in its response.

## 3. Configuration Schema (`settings.yaml`)

This section defines the structure of the `settings.yaml` configuration file.

```yaml
agent:
  name: "SIRS-LLM-Agent"
  version: "0.1.0"

logging:
  level: "INFO"
  file: "/var/log/agent.log"

api:
  host: "0.0.0.0"
  port: 8000

lm_studio:
  api_url: "http://localhost:1234/v1"
  # The API key should not be stored here.
  # It must be loaded from an environment variable (e.g., LM_STUDIO_API_KEY)
  # or a secure secrets management service.
```

## 4. Error Payload Structures

This section defines the structure for error messages.

```json
{
  "timestamp": "string",
  "error_code": "integer",
  "error_message": "string",
  "component": "string"
}
```

-   **timestamp**: An ISO 8601 formatted timestamp indicating when the error occurred.
   -   *Example*: `"2025-07-04T17:55:00Z"`
-   **component**: The part of the system where the error originated. Possible values include:
   -   `"SIRS_Model"`
   -   `"LLM_Client"`
   -   `"API_Server"`
-   **error_code**: An integer code mapped to a specific error type.

| Error Code | Error Type          |
|------------|---------------------|
| 1001       | Invalid Input       |
| 1002       | Authentication Error|
| 2001       | LLM API Error       |
| 2002       | SIRS Model Error    |
| 3001       | Internal Server Error|