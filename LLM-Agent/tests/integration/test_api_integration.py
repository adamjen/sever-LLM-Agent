import unittest
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient
import sys
import os
import json

# Add the project root to the Python path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..')))

from src.api.main import app, get_agent_core

# Create a mock to be injected
mock_agent_core = MagicMock()

def get_mock_agent_core_override():
    return mock_agent_core

# Use FastAPI's dependency_overrides to replace the real dependency with our mock
app.dependency_overrides[get_agent_core] = get_mock_agent_core_override

class TestApiIntegration(unittest.TestCase):

    def setUp(self):
        self.client = TestClient(app)
        # Reset the mock before each test
        mock_agent_core.reset_mock()
        # Explicitly clear side_effect to prevent it from leaking between tests
        mock_agent_core.process_query.side_effect = None

    def test_get_agent_status_success(self):
        # Arrange: Configure the mock to return a specific status
        expected_status = "All systems nominal"
        mock_agent_core.get_status.return_value = expected_status

        # Act: Call the API endpoint
        response = self.client.get("/api/v1/agent/status")

        # Assert: Check the HTTP response and the returned data
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": expected_status})
        mock_agent_core.get_status.assert_called_once()

    def test_query_agent_success(self):
        # Arrange: Configure the mock to return a specific response dictionary
        request_payload = {
            "session_id": "api-test-session-123",
            "prompt": "What is the weather like?",
            "context": "Location: London"
        }
        expected_response_data = {
            "session_id": "api-test-session-123",
            "response_text": "The agent says it is likely raining.",
            "confidence_score": 0.92
        }
        mock_agent_core.process_query.return_value = expected_response_data

        # Act: Call the API endpoint
        response = self.client.post("/api/v1/agent/query", json=request_payload)

        # Assert: Check the HTTP response and the returned data
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), expected_response_data)

        # Assert that the underlying agent core method was called correctly
        mock_agent_core.process_query.assert_called_once_with(
            session_id=request_payload["session_id"],
            prompt=request_payload["prompt"],
            context=request_payload["context"]
        )

    def test_query_agent_validation_error(self):
        # Arrange: Create a payload with a missing required field ("prompt")
        invalid_payload = {
            "session_id": "api-test-session-456"
            # "prompt" is missing
        }

        # Act: Call the API endpoint with the invalid payload
        response = self.client.post("/api/v1/agent/query", json=invalid_payload)

        # Assert: Check that we get a 422 Unprocessable Entity error
        self.assertEqual(response.status_code, 422)
        # FastAPI provides a detailed error message, we can check for key parts
        response_json = response.json()
        self.assertIn("detail", response_json)
        self.assertEqual(response_json["detail"][0]["msg"], "Field required")
        self.assertEqual(response_json["detail"][0]["loc"], ["body", "prompt"])

        # Ensure the agent core was NOT called
        mock_agent_core.process_query.assert_not_called()

    def test_generic_exception_handler(self):
        # Arrange: Configure the mock to raise an unexpected exception
        error_message = "A critical internal error occurred"
        mock_agent_core.process_query.side_effect = Exception(error_message)

        request_payload = {
            "session_id": "api-test-session-789",
            "prompt": "This will cause an error",
            "context": None
        }

        # Act & Assert: Use pytest.raises to check for the exception
        with self.assertRaises(Exception) as excinfo:
            self.client.post("/api/v1/agent/query", json=request_payload)
        
        self.assertIn(error_message, str(excinfo.exception))


if __name__ == '__main__':
    unittest.main()