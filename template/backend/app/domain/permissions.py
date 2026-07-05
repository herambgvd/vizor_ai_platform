"""__NAME__ domain permissions — registered into the shared catalog at import time.

Feature/scenario code declares its own permission keys so they appear in the role
editor and can gate routes. Imported by app/api so registration happens on startup.
"""

from __future__ import annotations

from edge.auth import PERMISSIONS, Permission


class ScenarioPerm:
    """__NAME__ permission keys. Extended per feature."""

    READ = "__SLUG__.read"
    MANAGE = "__SLUG__.manage"


PERMISSIONS.register(
    Permission(ScenarioPerm.READ, "View __NAME__", "__NAME__"),
    Permission(ScenarioPerm.MANAGE, "Manage __NAME__", "__NAME__"),
)
