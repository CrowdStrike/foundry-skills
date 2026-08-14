"""Shared pytest fixtures for foundry-skills script tests.

Adds skill-bundled script directories to sys.path so tests import the modules
by name, matching how scripts run in production. All API calls are mocked — no
CrowdStrike credentials are needed.
"""

import os
import sys

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_SCRIPT_DIRS = [
    os.path.join(_ROOT, "skills", "api-integrations", "scripts"),
    os.path.join(_ROOT, "skills", "development-workflow", "scripts"),
    os.path.join(_ROOT, "skills", "workflows-development", "scripts"),
]
for script_dir in _SCRIPT_DIRS:
    if script_dir not in sys.path:
        sys.path.insert(0, script_dir)
