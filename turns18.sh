#!/bin/bash
cd "$(dirname "$0")"
venv/bin/python3 turns18.py >> cron.log &
wait
