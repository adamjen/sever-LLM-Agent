import click
import requests
import json
import os
import sys

# Add the project root to the Python path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..')))

from agent_core.agent import AgentCore

# Configuration
API_BASE_URL = os.getenv("AGENT_API_URL", "http://127.0.0.1:8000/api/v1/agent")

def get_agent_status():
    """Checks the status of the agent API."""
    try:
        response = requests.get(f"{API_BASE_URL}/status")
        response.raise_for_status()
        return response.json().get("status")
    except requests.exceptions.RequestException as e:
        return f"Error connecting to agent API: {e}"

def query_agent(session_id: str, prompt: str, context: str | None = None):
    """Sends a query to the agent API."""
    payload = {"session_id": session_id, "prompt": prompt, "context": context}
    try:
        response = requests.post(f"{API_BASE_URL}/query", json=payload)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        return {"error": f"API request failed: {e}"}

@click.group()
def cli():
    """A CLI for interacting with the SIRS LLM Agent."""
    pass

@cli.command()
def status():
    """Get the status of the agent service."""
    click.echo("Checking agent status...")
    status_result = get_agent_status()
    click.echo(f"Agent status: {status_result}")

@cli.command()
@click.option('--session-id', default='cli-session-001', help='The session ID for the conversation.')
def chat(session_id):
    """Start an interactive chat session with the agent."""
    click.echo("Starting interactive chat session...")
    click.echo("Type 'quit' or 'exit' to end the session.")
    
    # Check agent status before starting
    if get_agent_status() != "ok":
        click.echo("Agent service is not available. Please start the service first.")
        return

    while True:
        prompt = click.prompt("You")
        if prompt.lower() in ['quit', 'exit']:
            click.echo("Ending chat session.")
            break
        
        response = query_agent(session_id, prompt)
        
        if "error" in response:
            click.secho(f"Agent Error: {response['error']}", fg="red")
        else:
            response_text = response.get('response_text', 'No response text.')
            confidence = response.get('confidence_score', 0.0)
            click.secho(f"Agent: {response_text} (Confidence: {confidence:.2f})", fg="green")

if __name__ == '__main__':
    cli()