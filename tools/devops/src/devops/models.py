"""
Custom types shared by the devops CLI modules: dataclasses and type aliases.
"""

from __future__ import annotations

from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path

from devops.run_log import RunLog

SubcommandFunction = Callable[[Path, Sequence[str], RunLog], int]


@dataclass(frozen=True)
class ContainerRunSettings:
    """
    What every `<binary> run` needs, whatever command it runs.
    `user_and_group_ids` is None to run as root. With `keep_zig_cache`, the Zig global cache
    lives in the named volume instead of the throwaway home.
    """

    container_binary: str
    repository_root: Path
    image: str
    user_and_group_ids: tuple[int, int] | None
    keep_zig_cache: bool = False
