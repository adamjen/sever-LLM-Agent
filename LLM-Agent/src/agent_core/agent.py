import requests
import json
import os
import logging

# --- Logging Setup ---
logger = logging.getLogger(__name__)

# Configuration
LM_STUDIO_ENDPOINT = os.getenv("LM_STUDIO_ENDPOINT", "http://localhost:1234/v1/chat/completions")
LM_STUDIO_MODEL = os.getenv("LM_STUDIO_MODEL", "local-model")

from sirs_integration.sirs_engine import SirsEngine

class AgentCore:
    """
    The core logic for the SIRS-based LLM Agent.
    """

    def __init__(self):
        self.sirs_engine = SirsEngine()

    def get_status(self) -> str:
        """Returns the current status of the agent."""
        return "ok"

    def process_query(self, session_id: str, prompt: str, context: str | None = None) -> dict:
        """
        Orchestrates the perception-inference-decision-action loop.
        """
        logger.info(f"[{session_id}] Starting query processing.")
        # 1. Perception: Process the incoming prompt and context.
        logger.info(f"[{session_id}] Perception: Processing prompt and context.")

        # 2. Inference: Interact with the SIRS engine.
        logger.info(f"[{session_id}] Inference: Running SIRS model.")
        sirs_output = self._run_sirs_inference(context)

        # 3. Decision: Generate a prompt for the LLM based on the original prompt and SIRS output.
        logger.info(f"[{session_id}] Decision: Preparing LLM prompt.")
        llm_prompt = self._prepare_llm_prompt(prompt, sirs_output)

        # 4. Action: Query the LLM and get a response.
        logger.info(f"[{session_id}] Action: Querying LLM.")
        llm_response = self._query_lm_studio(llm_prompt)

        # Format the final response
        final_response = {
            "session_id": session_id,
            "response_text": llm_response.get("choices", [{}])[0].get("message", {}).get("content", "No response from LLM."),
            "confidence_score": 0.85  # This would be calculated based on SIRS output in a real implementation
        }
        logger.info(f"[{session_id}] Query processing finished.")
        return final_response

    def _run_sirs_inference(self, context: str | None) -> dict:
        """
        Runs the SIRS model to get a probabilistic inference.
        """
        logger.info("Calling SIRS engine.")
        # This assumes a simple context-to-input mapping.
        # A real implementation would have more sophisticated logic.
        input_data = {"context": context}
        model_path = "LLM-Agent/models/sample_model.sirs.l" # This should be configurable
        result = self.sirs_engine.execute(model_path, input_data)
        if "error" in result:
            logger.error(f"SIRS Engine Error: {result['error']}")
        return result

    def _prepare_llm_prompt(self, user_prompt: str, sirs_output: dict) -> str:
        """
        Prepares the final prompt for the LLM.
        """
        logger.info("Preparing prompt for LLM.")
        # Combine user prompt with SIRS model output to create a richer prompt for the LLM.
        return f"""User Prompt: {user_prompt}

SIRS Model Inference: {json.dumps(sirs_output)}

Based on the probabilistic inference above, provide a comprehensive answer to the user's prompt.
"""

    def _query_lm_studio(self, prompt: str) -> dict:
        """
        Queries the LM Studio API to get a response from the LLM.
        """
        logger.info(f"Querying LM Studio at {LM_STUDIO_ENDPOINT}.")
        headers = {"Content-Type": "application/json"}
        payload = {
            "model": LM_STUDIO_MODEL,
            "messages": [
                {"role": "system", "content": "You are a helpful assistant."},
                {"role": "user", "content": prompt}
            ],
            "temperature": 0.7,
        }

        try:
            response = requests.post(LM_STUDIO_ENDPOINT, headers=headers, json=payload)
            response.raise_for_status()  # Raise an exception for bad status codes
            logger.info("Successfully received response from LM Studio.")
            return response.json()
        except requests.exceptions.RequestException as e:
            logger.error(f"Error connecting to LM Studio: {e}")
            return {"error": "Failed to connect to LM Studio."}
