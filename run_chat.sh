#!/bin/bash
cd LLM-Agent
source .venv/bin/activate
export PYTHONPATH=$PYTHONPATH:./src
python -m src.cli.cli chat