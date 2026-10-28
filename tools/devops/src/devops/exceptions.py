"""
Exceptions raised by the devops CLI. Each message says what went wrong and what to fix.
"""

from __future__ import annotations


class ContainerSetupError(Exception):
    """
    The container cannot be used as configured. The message says what to fix.
    """


class ZigCleanupRefusedError(Exception):
    """
    A path was chosen for removal that cleanup must never touch. The message names it.
    """
