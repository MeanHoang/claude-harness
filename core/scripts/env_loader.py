"""
Shared .env.debug loader for debug scripts.

Searches upward from the script directory to find .env.debug,
parses it, and sets env vars (without overriding existing ones).
"""

import os


def load_env_debug():
    """Find and load .env.debug from project root."""
    # Walk up from this script's directory to find .env.debug
    current = os.path.dirname(os.path.abspath(__file__))
    for _ in range(10):  # max 10 levels up
        env_file = os.path.join(current, ".env.agent")
        if os.path.exists(env_file):
            _parse_env_file(env_file)
            return env_file
        parent = os.path.dirname(current)
        if parent == current:
            break
        current = parent
    return None


def _parse_env_file(path):
    """Parse KEY=VALUE lines from env file. Does not override existing env vars."""
    env_dir = os.path.dirname(os.path.abspath(path))
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            # Expand ~ in paths
            if value.startswith("~"):
                value = os.path.expanduser(value)
            # Resolve relative paths (for file path values)
            elif not value.startswith("/") and os.sep in value or "/" in value:
                resolved = os.path.join(env_dir, value)
                if os.path.exists(resolved):
                    value = os.path.abspath(resolved)
            # Don't override existing env vars
            if key not in os.environ:
                os.environ[key] = value