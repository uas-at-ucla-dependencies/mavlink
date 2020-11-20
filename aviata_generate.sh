#!/bin/bash
git submodule update --init --recursive
python -m pymavlink.tools.mavgen --lang=C --wire-protocol=2.0 --output=generated/include/mavlink/v2.0 message_definitions/v1.0/aviata.xml
