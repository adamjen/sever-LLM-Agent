import subprocess
import json
import os
import logging

# --- Logging Setup ---
logger = logging.getLogger(__name__)

# Configuration
# This should point to the compiled Zig executable
SIRS_EXECUTABLE_PATH = os.getenv("SIRS_EXECUTABLE_PATH", "./sirs_engine")

class SirsEngine:
    """
    A wrapper to communicate with the Zig-based SIRS engine.
    """

    def __init__(self, executable_path: str = SIRS_EXECUTABLE_PATH):
        self.executable_path = executable_path
        if not os.path.exists(self.executable_path):
            # Note: In a real scenario, we might want to compile it
            # or provide better error handling.
            logger.warning(f"SIRS executable not found at '{self.executable_path}'")

    def execute(self, model_path: str, input_data: dict) -> dict:
        """
        Executes the SIRS model with the given input data.
        
        Args:
            model_path: The path to the .sirs.l model file.
            input_data: A dictionary representing the input for the model.

        Returns:
            A dictionary with the model's output.
        """
        logger.info(f"Executing SIRS model '{model_path}' with input: {input_data}")
        if not os.path.exists(self.executable_path):
            logger.error(f"SIRS executable not found at {self.executable_path}")
            return {"error": f"SIRS executable not found at {self.executable_path}"}
        
        if not os.path.exists(model_path):
            logger.error(f"SIRS model file not found at {model_path}")
            return {"error": f"SIRS model file not found at {model_path}"}

        command = [self.executable_path, "--model", model_path]
        
        try:
            process = subprocess.Popen(
                command,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            
            # Send data to the engine's stdin
            stdout, stderr = process.communicate(input=json.dumps(input_data))
            
            if process.returncode != 0:
                logger.error(f"SIRS engine process failed. Stderr: {stderr}")
                return {"error": "SIRS engine process failed", "details": stderr}
            
            logger.info("SIRS model executed successfully.")
            # Parse the JSON output from the engine's stdout
            return json.loads(stdout)

        except FileNotFoundError:
            logger.error(f"Could not find the SIRS executable at '{self.executable_path}'.")
            return {"error": f"Could not find the SIRS executable at '{self.executable_path}'."}
        except json.JSONDecodeError:
            logger.error("Failed to decode JSON response from SIRS engine.")
            return {"error": "Failed to decode JSON response from SIRS engine."}
        except Exception as e:
            logger.error(f"An unexpected error occurred while running the SIRS engine: {e}")
            return {"error": f"An unexpected error occurred while running the SIRS engine: {e}"}
