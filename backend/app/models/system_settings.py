from __future__ import annotations

from pydantic import BaseModel, Field


class SystemSettingsUpdate(BaseModel):
    default_daily_limit_minutes: int | None = Field(
        default=None,
        ge=1,
        le=1440,
    )

    app_blocking_enabled: bool | None = None
    focus_mode_enabled: bool | None = None
    cooldown_timer_enabled: bool | None = None
    scheduled_lock_enabled: bool | None = None
    category_restriction_enabled: bool | None = None
    emergency_access_enabled: bool | None = None

from pydantic import ConfigDict


class SystemPatchSettings(SystemSettingsUpdate):
    """Settings block of a system patch. Unknown keys and wrongly-typed
    values are rejected instead of silently coerced or dropped."""

    model_config = ConfigDict(extra="forbid", strict=True)


class SystemPatchRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    version: str | None = Field(default=None, max_length=40)
    description: str | None = Field(default=None, max_length=200)
    settings: SystemPatchSettings
    validate_only: bool = False
