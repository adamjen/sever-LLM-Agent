import unittest
from unittest.mock import patch, MagicMock
from click.testing import CliRunner
import sys
import os
import json

# Add the project root to the Python path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..')))

from src.cli.cli import cli

class TestCliIntegration(unittest.TestCase):

    def setUp(self):
        self.runner = CliRunner()

    @patch('src.cli.cli.get_agent_status')
    def test_status_command_success(self, mock_get_status):
        # Arrange
        mock_get_status.return_value = "ok"
        
        # Act
        result = self.runner.invoke(cli, ['status'])
        
        # Assert
        self.assertEqual(result.exit_code, 0)
        self.assertIn("Checking agent status...", result.output)
        self.assertIn("Agent status: ok", result.output)
        mock_get_status.assert_called_once()

    @patch('src.cli.cli.get_agent_status')
    def test_status_command_error(self, mock_get_status):
        # Arrange
        error_message = "Connection refused"
        mock_get_status.return_value = f"Error connecting to agent API: {error_message}"
        
        # Act
        result = self.runner.invoke(cli, ['status'])
        
        # Assert
        self.assertEqual(result.exit_code, 0)
        self.assertIn(f"Agent status: Error connecting to agent API: {error_message}", result.output)
        mock_get_status.assert_called_once()

    @patch('src.cli.cli.get_agent_status')
    @patch('src.cli.cli.query_agent')
    def test_chat_command_successful_interaction(self, mock_query_agent, mock_get_status):
        # Arrange
        mock_get_status.return_value = "ok"
        mock_query_agent.return_value = {
            "response_text": "The agent's answer.",
            "confidence_score": 0.95
        }
        
        # Act
        # Simulate user typing "hello" and then "quit"
        result = self.runner.invoke(cli, ['chat', '--session-id', 'test-chat-session'], input='hello\nquit\n')
        
        # Assert
        self.assertEqual(result.exit_code, 0)
        self.assertIn("Starting interactive chat session...", result.output)
        self.assertIn("Agent: The agent's answer. (Confidence: 0.95)", result.output)
        self.assertIn("Ending chat session.", result.output)
        
        # Verify mocks were called correctly
        mock_get_status.assert_called_once()
        mock_query_agent.assert_called_once_with('test-chat-session', 'hello')

    @patch('src.cli.cli.get_agent_status')
    def test_chat_command_agent_not_available(self, mock_get_status):
        # Arrange
        mock_get_status.return_value = "error"
        
        # Act
        result = self.runner.invoke(cli, ['chat'])
        
        # Assert
        self.assertEqual(result.exit_code, 0)
        self.assertIn("Agent service is not available.", result.output)
        mock_get_status.assert_called_once()

    @patch('src.cli.cli.get_agent_status')
    @patch('src.cli.cli.query_agent')
    def test_chat_command_api_error(self, mock_query_agent, mock_get_status):
        # Arrange
        mock_get_status.return_value = "ok"
        mock_query_agent.return_value = {"error": "Internal Server Error"}
        
        # Act
        result = self.runner.invoke(cli, ['chat'], input='test prompt\nquit\n')
        
        # Assert
        self.assertEqual(result.exit_code, 0)
        self.assertIn("Agent Error: Internal Server Error", result.output)
        mock_query_agent.assert_called_once_with('cli-session-001', 'test prompt')

if __name__ == '__main__':
    unittest.main()