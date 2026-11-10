"""Every adapter, keyed by the registry's kind."""
from ..model import Adapter
from .env import EnvAdapter
from .macos_default import MacosDefaultAdapter
from .package import PackageAdapter

ADAPTERS: dict[str, Adapter] = {"env": EnvAdapter(), "macos-default": MacosDefaultAdapter(), "package": PackageAdapter()}
