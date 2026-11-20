from __future__ import annotations

from pydantic import BaseModel, Field


class SystemSettingsUpdate(BaseModel):
    """System-wide release settings, set by the admin through a validated
    system patch and read live by every WellScreen phone
    (system_settings/global).

    minimum_app_version: phones running an older app version are asked to
    update before continuing (how a bug-fix release reaches every phone).
    maintenance_message: a short notice shown to every user; "" clears it.
    """

    minimum_app_version: str | None = Field(
        default=None,
        pattern=r"^\d{1,3}\.\d{1,3}\.\d{1,3}$",
    )
    maintenance_message: str | None = Field(default=None, max_length=200)

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
