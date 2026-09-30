"""Runtime configuration. Secrets come from the environment or an untracked .env file."""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

BOT_DIR = Path(__file__).resolve().parent.parent


def _load_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.is_file():
        return values
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


@dataclass(frozen=True)
class Settings:
    signing_secret: str = field(default="", repr=False)
    bot_token: str = field(default="", repr=False)
    bot_user_id: str = ""
    approvers: frozenset[str] = frozenset()
    audit_log_path: Path = BOT_DIR / "chatops-audit.log"
    queue_db_path: Path = BOT_DIR / "queue.db"
    namespace: str = "insighthub-local"
    readonly_kubeconfig: str = str(Path.home() / ".kube" / "insighthub-mcp-readonly.kubeconfig")
    mutator_kubeconfig: str = str(Path.home() / ".kube" / "insighthub-chatops-mutator.kubeconfig")
    prometheus_url: str = "http://localhost:9090"
    replay_window_seconds: int = 300
    approval_ttl_seconds: int = 60
    max_attempts: int = 3
    backoff_base_seconds: float = 1.0
    scale_min: int = 1
    scale_max: int = 5
    scalable: frozenset[str] = frozenset({"insighthub-api", "insighthub-ingestion-worker"})

    @property
    def ready(self) -> bool:
        return bool(self.signing_secret and self.bot_token)

    @classmethod
    def from_env(cls) -> "Settings":
        env = {**_load_env_file(BOT_DIR / ".env"), **os.environ}
        home = Path.home()
        return cls(
            signing_secret=env.get("SLACK_SIGNING_SECRET", ""),
            bot_token=env.get("SLACK_BOT_TOKEN", ""),
            bot_user_id=env.get("SLACK_BOT_USER_ID", ""),
            approvers=frozenset(x.strip() for x in env.get("CHATOPS_APPROVERS", "").split(",") if x.strip()),
            audit_log_path=Path(env.get("CHATOPS_AUDIT_LOG", str(BOT_DIR / "chatops-audit.log"))),
            queue_db_path=Path(env.get("CHATOPS_QUEUE_DB", str(BOT_DIR / "queue.db"))),
            namespace=env.get("CHATOPS_NAMESPACE", "insighthub-local"),
            readonly_kubeconfig=env.get("CHATOPS_READONLY_KUBECONFIG",
                                        str(home / ".kube" / "insighthub-mcp-readonly.kubeconfig")),
            mutator_kubeconfig=env.get("CHATOPS_MUTATOR_KUBECONFIG",
                                       str(home / ".kube" / "insighthub-chatops-mutator.kubeconfig")),
            prometheus_url=env.get("PROMETHEUS_URL", "http://localhost:9090"),
        )
