"""Every adapter, keyed by the registry's kind."""
from ..model import Adapter
from .dotfile import DotfileAdapter
from .env import EnvAdapter
from .macos_default import MacosDefaultAdapter
from .module import ModuleAdapter
from .package import PackageAdapter
from .tool import ToolAdapter

ADAPTERS: dict[str, Adapter] = {"env": EnvAdapter(), "macos-default": MacosDefaultAdapter(), "package": PackageAdapter(),
                                "dotfile": DotfileAdapter(), "tool": ToolAdapter(), "module": ModuleAdapter()}
