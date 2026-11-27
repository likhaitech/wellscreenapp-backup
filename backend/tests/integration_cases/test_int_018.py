
import datetime as dt

from app.services import system_activity_service as activity

from ..cases.case_report import run_case
from .int_fixture import NOW, pair_child, system  # noqa: F401


def test_int_018(system):
    db = system.db

    def body() -> str:
        profile_id = pair_child(system)
        today = activity.manila_day(NOW)

        activity.refresh_daily_activity(now=NOW, db=db)
        before = activity.admin_overview(days=7, now=NOW, db=db)["daily"][-1]
        assert before["date"] == today and before["activeChildren"] == 0

        db.docs[f"child_profiles/{profile_id}"]["lastSeenAt"] = NOW - dt.timedelta(minutes=3)


        counted = activity.refresh_daily_activity(now=NOW, db=db)
        assert counted["activeChildren"] == 1
        after = activity.admin_overview(days=7, now=NOW, db=db)["daily"][-1]
        assert after["date"] == today and after["activeChildren"] == 1
        return (f"Before the check-in the Active users graph showed 0 child devices for "
                f"{today}; after the paired phone checked in it shows 1 active child device "
                "for that day")

    run_case(
        "INT-018",
        file="backend/tests/integration_cases/test_int_018.py",
        code_tested="backend/app/services/system_activity_service.py",
        description="Administrator views Active users (System Administration -> Usage Monitoring).",
        expected="The child device is counted in the Active users graph for that day.",
        body=body,
    )
