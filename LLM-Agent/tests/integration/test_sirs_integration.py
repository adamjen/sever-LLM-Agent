import unittest
from unittest.mock import patch, MagicMock
import json
import os
import sys
import subprocess

# Add the src directory to the Python path to allow imports
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../../src')))

from sirs_integration.sirs_engine import SirsEngine

class TestSirsEngineIntegration(unittest.TestCase):

    def setUp(self):
        # Set a dummy executable path for testing
        self.dummy_executable_path = "./dummy_sirs_engine"
        self.dummy_model_path = "LLM-Agent/models/sample_model.sirs.l"
        self.sirs_engine = SirsEngine(executable_path=self.dummy_executable_path)
        self.input_data = {"param1": "value1", "param2": 123}

        # Create dummy files for testing existence checks
        with open(self.dummy_executable_path, 'w') as f:
            f.write("#!/bin/bash\necho 'dummy'")
        os.chmod(self.dummy_executable_path, 0o755) # Make it executable

        os.makedirs(os.path.dirname(self.dummy_model_path), exist_ok=True)
        with open(self.dummy_model_path, 'w') as f:
            f.write("dummy model content")

    def tearDown(self):
        # Clean up dummy files
        if os.path.exists(self.dummy_executable_path):
            os.remove(self.dummy_executable_path)
        if os.path.exists(self.dummy_model_path):
            os.remove(self.dummy_model_path)
        if os.path.exists(os.path.dirname(self.dummy_model_path)):
            try:
                os.rmdir(os.path.dirname(self.dummy_model_path))
            except OSError:
                pass # Directory might not be empty if other tests create files

    @patch('sirs_integration.sirs_engine.subprocess.Popen')
    def test_execute_success(self, mock_popen):
        # Configure the mock process for a successful run
        mock_process = MagicMock()
        mock_process.communicate.return_value = (json.dumps({"output": "success"}), "")
        mock_process.returncode = 0
        mock_popen.return_value = mock_process

        result = self.sirs_engine.execute(self.dummy_model_path, self.input_data)

        mock_popen.assert_called_once_with(
            [self.dummy_executable_path, "--model", self.dummy_model_path],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        mock_process.communicate.assert_called_once_with(input=json.dumps(self.input_data))
        self.assertEqual(result, {"output": "success"})

    @patch('sirs_integration.sirs_engine.subprocess.Popen')
    def test_execute_process_failure(self, mock_popen):
        # Configure the mock process for a failed run (non-zero return code)
        mock_process = MagicMock()
        mock_process.communicate.return_value = ("", "Error: Something went wrong.")
        mock_process.returncode = 1 # Simulate an error
        mock_popen.return_value = mock_process

        result = self.sirs_engine.execute(self.dummy_model_path, self.input_data)

        self.assertEqual(result["error"], "SIRS engine process failed")
        self.assertIn("Error: Something went wrong.", result["details"])

    @patch('sirs_integration.sirs_engine.subprocess.Popen')
    def test_execute_json_decode_error(self, mock_popen):
        # Configure the mock process to return invalid JSON
        mock_process = MagicMock()
        mock_process.communicate.return_value = ("invalid json", "")
        mock_process.returncode = 0
        mock_popen.return_value = mock_process

        result = self.sirs_engine.execute(self.dummy_model_path, self.input_data)

        self.assertEqual(result["error"], "Failed to decode JSON response from SIRS engine.")

    @patch('sirs_integration.sirs_engine.os.path.exists', side_effect=[False, True]) # executable not found first, then model found
    def test_execute_executable_not_found(self, mock_exists):
        # Test when the executable path does not exist
        # We need to mock os.path.exists to simulate the file not being there
        # The setUp creates the file, so we need to control mock_exists carefully
        # side_effect=[False, True] means first call returns False, second returns True
        # This simulates the check for executable_path failing, then model_path succeeding
        result = self.sirs_engine.execute(self.dummy_model_path, self.input_data)
        self.assertEqual(result["error"], f"SIRS executable not found at {self.dummy_executable_path}")
        mock_exists.assert_any_call(self.dummy_executable_path) # Ensure this was checked

    @patch('sirs_integration.sirs_engine.os.path.exists', side_effect=[True, False]) # executable found, then model not found
    def test_execute_model_not_found(self, mock_exists):
        # Test when the model path does not exist
        result = self.sirs_engine.execute("non_existent_model.sirs.l", self.input_data)
        self.assertEqual(result["error"], "SIRS model file not found at non_existent_model.sirs.l")
        mock_exists.assert_any_call("non_existent_model.sirs.l") # Ensure this was checked

    @patch('sirs_integration.sirs_engine.subprocess.Popen', side_effect=FileNotFoundError("Executable not found"))
    def test_execute_file_not_found_exception(self, mock_popen):
        # Simulate FileNotFoundError during Popen call
        result = self.sirs_engine.execute(self.dummy_model_path, self.input_data)
        self.assertEqual(result["error"], f"Could not find the SIRS executable at '{self.dummy_executable_path}'.")

    @patch('sirs_integration.sirs_engine.subprocess.Popen', side_effect=Exception("Generic error"))
    def test_execute_generic_exception(self, mock_popen):
        # Simulate a generic exception during Popen call
        result = self.sirs_engine.execute(self.dummy_model_path, self.input_data)
        self.assertIn("An unexpected error occurred", result["error"])
        self.assertIn("Generic error", result["error"])

if __name__ == '__main__':
    unittest.main()