#!/bin/bash
cd LLM-Agent
export SIRS_EXECUTABLE_PATH=../dist/sev
source .venv/bin/activate
export PYTHONPATH=$PYTHONPATH:./src
uvicorn api.main:app --reload