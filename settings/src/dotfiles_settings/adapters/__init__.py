"""Every adapter, keyed by the registry's kind."""
from ..model import Adapter
from .env import EnvAdapter

ADAPTERS: dict[str, Adapter] = {"env": EnvAdapter()}
