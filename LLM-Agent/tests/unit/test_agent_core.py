import unittest
from unittest.mock import patch, MagicMock
import json
import os
import sys
import requests # Added import for requests

# Add the src directory to the Python path to allow imports
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../../src')))

from agent_core.agent import AgentCore # This import might still be an issue due to relative pathing

class TestAgentCore(unittest.TestCase):

    @patch('agent_core.agent.SirsEngine')
    def setUp(self, MockSirsEngine):
        self.mock_sirs_engine_instance = MockSirsEngine.return_value
        self.agent = AgentCore()
        self.session_id = "test-session-123"
        self.user_prompt = "What is the probability of rain tomorrow?"
        self.context = "weather data"

    def test_get_status(self):
        self.assertEqual(self.agent.get_status(), "ok")

    @patch('agent_core.agent.AgentCore._run_sirs_inference')
    @patch('agent_core.agent.AgentCore._prepare_llm_prompt')
    @patch('agent_core.agent.AgentCore._query_lm_studio')
    def test_process_query_success(self, mock_query_lm_studio, mock_prepare_llm_prompt, mock_run_sirs_inference):
        # Mock return values for internal methods
        mock_run_sirs_inference.return_value = {"sirs_result": "some_inference"}
        mock_prepare_llm_prompt.return_value = "prepared_llm_prompt"
        mock_query_lm_studio.return_value = {
            "choices": [{"message": {"content": "LLM response text."}}]
        }

        response = self.agent.process_query(self.session_id, self.user_prompt, self.context)

        # Assert that internal methods were called with correct arguments
        mock_run_sirs_inference.assert_called_once_with(self.context)
        mock_prepare_llm_prompt.assert_called_once_with(self.user_prompt, {"sirs_result": "some_inference"})
        mock_query_lm_studio.assert_called_once_with("prepared_llm_prompt")

        # Assert the final response structure and content
        self.assertIsInstance(response, dict)
        self.assertEqual(response["session_id"], self.session_id)
        self.assertEqual(response["response_text"], "LLM response text.")
        self.assertIn("confidence_score", response)

    def test_run_sirs_inference_success(self):
        self.mock_sirs_engine_instance.execute.return_value = {"sirs_output": "data"}
        result = self.agent._run_sirs_inference(self.context)
        self.mock_sirs_engine_instance.execute.assert_called_once_with(
            "LLM-Agent/models/sample_model.sirs.l", {"context": self.context}
        )
        self.assertEqual(result, {"sirs_output": "data"})

    def test_run_sirs_inference_error(self):
        self.mock_sirs_engine_instance.execute.return_value = {"error": "SIRS error"}
        result = self.agent._run_sirs_inference(self.context)
        self.assertEqual(result, {"error": "SIRS error"})

    def test_prepare_llm_prompt(self):
        sirs_output = {"inference": "high probability"}
        expected_prompt = f"""User Prompt: {self.user_prompt}

SIRS Model Inference: {json.dumps(sirs_output)}

Based on the probabilistic inference above, provide a comprehensive answer to the user's prompt.
"""
        prompt = self.agent._prepare_llm_prompt(self.user_prompt, sirs_output)
        self.assertEqual(prompt, expected_prompt)

    @patch('agent_core.agent.requests.post')
    def test_query_lm_studio_success(self, mock_post):
        mock_response = MagicMock()
        mock_response.raise_for_status.return_value = None
        mock_response.json.return_value = {"choices": [{"message": {"content": "LLM says hello."}}]}
        mock_post.return_value = mock_response

        prompt = "Hello LLM"
        response = self.agent._query_lm_studio(prompt)
        self.assertEqual(response["choices"][0]["message"]["content"], "LLM says hello.")
        mock_post.assert_called_once()

    @patch('agent_core.agent.requests.post')
    def test_query_lm_studio_failure(self, mock_post):
        mock_post.side_effect = requests.exceptions.RequestException("Connection error")
        prompt = "Hello LLM"
        response = self.agent._query_lm_studio(prompt)
        self.assertEqual(response, {"error": "Failed to connect to LM Studio."})
        mock_post.assert_called_once()

if __name__ == '__main__':
    unittest.main()