from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


class SystemSettingsUpdate(BaseModel):
    """Age-group rules the guardian and child apps read from
    system_settings/global (manuscript Ch. III age table).

    goal_minutes_*: the default daily screen-time goal for that age group.
    risky_sites_*: what happens on a "possible risk" website - "block" it,
    or "review" (ask the guardian). Known harmful sites are always blocked.
    """

    goal_minutes_6_and_below: int | None = Field(default=None, ge=15, le=720)
    goal_minutes_7_12: int | None = Field(default=None, ge=15, le=720)
    goal_minutes_13_15: int | None = Field(default=None, ge=15, le=720)

    risky_sites_6_and_below: Literal["block", "review"] | None = None
    risky_sites_7_12: Literal["block", "review"] | None = None
    risky_sites_13_15: Literal["block", "review"] | None = None

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
