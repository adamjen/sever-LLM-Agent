import logging
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import sys
import os
from dotenv import load_dotenv

# --- Load Environment Variables ---
# Load .env file from the LLM-Agent directory, which is one level up from src/api
dotenv_path = os.path.join(os.path.dirname(__file__), '..', '..', '.env')
load_dotenv(dotenv_path=dotenv_path)


# --- Logging Setup ---
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Add the project root to the Python path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..')))

from agent_core.agent import AgentCore

app = FastAPI(
    title="SIRS LLM Agent API",
    description="API for interacting with the SIRS-based LLM Agent.",
    version="0.1.0",
)

# --- Pydantic Models ---

class AgentQueryRequest(BaseModel):
    session_id: str
    prompt: str
    context: str | None = None

class AgentQueryResponse(BaseModel):
    session_id: str
    response_text: str
    confidence_score: float

class AgentStatusResponse(BaseModel):
    status: str

# --- Agent Core Initialization ---

agent_core = AgentCore()


# --- Middleware and Exception Handling ---

@app.exception_handler(Exception)
async def generic_exception_handler(request: Request, exc: Exception):
    return JSONResponse(
        status_code=500,
        content={"message": f"An unexpected error occurred: {exc}"},
    )

# --- API Endpoints ---

@app.get("/api/v1/agent/status", response_model=AgentStatusResponse)
async def get_agent_status():
    """
    Retrieves the current status of the agent.
    """
    logger.info("Status endpoint was called.")
    status = agent_core.get_status()
    return AgentStatusResponse(status=status)

@app.post("/api/v1/agent/query", response_model=AgentQueryResponse)
async def query_agent(request: AgentQueryRequest):
    """
    Submits a query to the agent and receives a response.
    """
    logger.info(f"Query received for session_id: {request.session_id}")
    # The response from AgentCore is a dict, we need to convert it to the Pydantic model
    response_data = agent_core.process_query(
        session_id=request.session_id,
        prompt=request.prompt,
        context=request.context
    )
    logger.info(f"Responding to session_id: {request.session_id}")
    return AgentQueryResponse(**response_data)

# To run this service, use the command:
# uvicorn LLM-Agent.src.api.main:app --reload