#!/bin/bash
#
# run this via cron--6:30am everyday
#30 06 * * *	/home/plchuser/chpl-patron-turns-18.sh
cd "$(dirname "$0")"
venv/bin/python3 turns18.py >> cron.log &
wait
