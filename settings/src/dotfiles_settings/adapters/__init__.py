"""Every adapter, keyed by the registry's kind."""
from ..model import Adapter
from .env import EnvAdapter
from .macos_default import MacosDefaultAdapter

ADAPTERS: dict[str, Adapter] = {"env": EnvAdapter(), "macos-default": MacosDefaultAdapter()}
