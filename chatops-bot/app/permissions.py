"""Three-tier permissions: read (auto), write (ask + confirm token), destructive (denied).

Approval tokens are single-use, expire, and are bound to (user, action, arguments).
"""
from __future__ import annotations

import secrets
import threading
import time
from dataclasses import dataclass
from enum import Enum
from typing import Any, Callable

from .settings import Settings


class Tier(str, Enum):
    READ = "read"
    WRITE = "write"
    DESTRUCTIVE = "destructive"


@dataclass(frozen=True)
class Verdict:
    decision: str  # allowed | denied | approval_required
    reason: str = ""


def authorize(settings: Settings, user: str, tier: Tier, args: dict[str, Any] | None = None) -> Verdict:
    """Decide whether `user` may start an action of `tier`; writes still need a confirm token."""
    if tier is Tier.READ:
        return Verdict("allowed")
    if tier is Tier.DESTRUCTIVE:
        return Verdict("denied", "destructive_actions_disabled")
    args = args or {}
    if user not in settings.approvers:
        return Verdict("denied", "user_not_approver")
    deployment = args.get("deployment")
    if deployment not in settings.scalable:
        return Verdict("denied", "deployment_not_allowed")
    replicas = args.get("replicas")
    if type(replicas) is not int or not settings.scale_min <= replicas <= settings.scale_max:
        return Verdict("denied", "replicas_out_of_range")
    return Verdict("approval_required", "confirmation_required")


@dataclass(frozen=True)
class Approval:
    token: str
    user: str
    action: str
    args: dict[str, Any]
    expires_at: float


class ApprovalError(Exception):
    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


class ApprovalStore:
    def __init__(self, ttl_seconds: int = 60, clock: Callable[[], float] = time.time) -> None:
        self.ttl = ttl_seconds
        self._clock = clock
        self._items: dict[str, Approval] = {}
        self._lock = threading.Lock()

    def issue(self, user: str, action: str, args: dict[str, Any]) -> Approval:
        token = secrets.token_hex(4).upper()
        approval = Approval(token, user, action, dict(args), self._clock() + self.ttl)
        with self._lock:
            self._items[token] = approval
        return approval

    def redeem(self, token: str, user: str, action: str | None = None,
               args: dict[str, Any] | None = None) -> Approval:
        """Consume a token. A wrong user/action/args attempt is refused and leaves the token intact."""
        with self._lock:
            approval = self._items.get(token.upper())
            if approval is None:
                raise ApprovalError("unknown_token")
            if self._clock() >= approval.expires_at:
                del self._items[approval.token]
                raise ApprovalError("token_expired")
            if user != approval.user:
                raise ApprovalError("token_bound_to_other_user")
            if (action is not None and action != approval.action) or \
                    (args is not None and args != approval.args):
                raise ApprovalError("token_bound_to_other_action")
            del self._items[approval.token]
            return approval
