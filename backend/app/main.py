from collections import OrderedDict, deque
from collections.abc import Awaitable, Callable
import ipaddress
import math
import os
from threading import Lock
import time

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response

from .routes.admin_users import router as admin_users_router
from .routes.admin_settings import router as admin_settings_router
from .routes.admin_logs import router as admin_logs_router
from .routes.alerts import router as alerts_router
from .routes.parent_child_chat import router as parent_child_chat_router
from .routes.monitoring import router as monitoring_router
from .routes.pairing import router as pairing_router
from .routes.data_cleanup import router as data_cleanup_router


class InMemoryRateLimiter:
    """Bounded, thread-safe sliding window, shared by all HTTP routes.

    Each backend process has its own counters. No database calls are needed.
    """

    def __init__(
        self,
        requests_per_window: int = 240,
        window_seconds: int = 60,
        max_clients: int = 4096,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        if min(requests_per_window, window_seconds, max_clients) <= 0:
            raise ValueError("Rate-limit settings must be positive")
        self.limit = requests_per_window
        self.window_seconds = window_seconds
        self.max_clients = max_clients
        self._clock = clock
        # Ordered by most recent admitted request, oldest first.
        self._buckets: OrderedDict[str, deque[float]] = OrderedDict()
        self._lock = Lock()

    def check(self, client: str) -> int | None:
        """Return None for an allowed request or retry delay in seconds."""
        with self._lock:
            now = self._clock()
            cutoff = now - self.window_seconds

            # Expire inactive clients without retaining their IPs forever.
            while self._buckets:
                oldest = next(iter(self._buckets.values()))
                if oldest[-1] > cutoff:
                    break
                self._buckets.popitem(last=False)

            bucket = self._buckets.get(client)
            if bucket is None:
                if len(self._buckets) >= self.max_clients:
                    # Do not evict live counters (that would let requests
                    # reset existing limits). Retry when a slot can expire.
                    oldest = next(iter(self._buckets.values()))
                    return max(1, math.ceil(oldest[-1] + self.window_seconds - now))
                bucket = deque()
                self._buckets[client] = bucket

            while bucket and bucket[0] <= cutoff:
                bucket.popleft()

            if len(bucket) >= self.limit:
                return max(1, math.ceil(bucket[0] + self.window_seconds - now))

            bucket.append(now)
            self._buckets.move_to_end(client)
            return None


def _client_key(request: Request) -> str:
    # Render's public web ingress overwrites CF-Connecting-IP. Do not parse
    # the leftmost X-Forwarded-For value, which can be supplied by a caller.
    # This deployment assumes only trusted services use Render's private
    # network; if that changes, revisit the trusted proxy boundary.
    if os.getenv("RENDER") == "true":
        raw = request.headers.get("CF-Connecting-IP", "")
        try:
            return str(ipaddress.ip_address(raw))
        except ValueError:
            # Unknown ingress clients share a conservative fallback bucket.
            # Render's default proxy settings can trust forwarded addresses,
            # so do not use request.client as a fallback on this platform.
            return "render-unidentified"

    # Local development / tests: use the ASGI client, not untrusted headers.
    return request.client.host if request.client else "unknown"


# The interactive API docs (/docs, /redoc, /openapi.json) list every
# endpoint, so they are off on the live server. Set
# WELLSCREEN_ENABLE_API_DOCS=1 locally to turn them on for development.
_API_DOCS_ENABLED = os.getenv("WELLSCREEN_ENABLE_API_DOCS", "").strip() in {
    "1",
    "true",
    "yes",
}

app = FastAPI(
    title="WellScreen Backend",
    version="1.0.0",
    description="Administrative backend API for WellScreen.",
    docs_url="/docs" if _API_DOCS_ENABLED else None,
    redoc_url="/redoc" if _API_DOCS_ENABLED else None,
    openapi_url="/openapi.json" if _API_DOCS_ENABLED else None,
)

rate_limiter = InMemoryRateLimiter()


@app.middleware("http")
async def enforce_rate_limit(
    request: Request,
    call_next: Callable[[Request], Awaitable[Response]],
) -> Response:
    # Keep Render health checks available, even for a throttled client.
    if request.url.path == "/health" and request.method in {"GET", "HEAD"}:
        return await call_next(request)

    retry_after = rate_limiter.check(_client_key(request))
    if retry_after is not None:
        return JSONResponse(
            status_code=429,
            content={"detail": "Too many requests. Please try again later."},
            headers={
                "Retry-After": str(retry_after),
                "Cache-Control": "no-store",
            },
        )

    return await call_next(request)


@app.get("/health", tags=["Health"])
def health() -> dict[str, str]:
    return {"status": "ok"}


# Register API routers
app.include_router(admin_users_router)
app.include_router(admin_settings_router)
app.include_router(admin_logs_router)
app.include_router(alerts_router)
app.include_router(parent_child_chat_router)
app.include_router(monitoring_router)
app.include_router(pairing_router)
app.include_router(data_cleanup_router)
