#!/bin/bash
# This script sets the PYTHONPATH to include the LLM-Agent/src directory
# and then executes the LLM-Agent CLI command from the project root.
PYTHONPATH=./LLM-Agent/src python3 -m LLM-Agent.src.cli.cli status