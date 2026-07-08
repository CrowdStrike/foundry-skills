"""Shared pytest fixtures for foundry-skills script tests.

Adds scripts/ to sys.path so tests import the modules by name, matching how
the scripts are invoked at runtime. All API calls are mocked — no CrowdStrike
credentials are needed.
"""

import os
import sys

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_SCRIPTS = os.path.join(_ROOT, "scripts")
if _SCRIPTS not in sys.path:
    sys.path.insert(0, _SCRIPTS)
