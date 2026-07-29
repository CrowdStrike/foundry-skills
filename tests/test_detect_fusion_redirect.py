"""Tests for scripts/detect_fusion_redirect.py.

Ported from the standalone scripts/test_detect_fusion_redirect.py assertion
script to pytest so it runs under the coverage-gated CI job. No network or
credentials needed — every case operates on plain string inputs.

Note: conftest.py puts scripts/ on sys.path so the import works.
"""

import detect_fusion_redirect as detect


# ── Standalone Fusion workflows — SHOULD redirect to fusion-skills ──────────


def test_contain_host_on_detection_redirects():
    result = detect.classify(
        "Build a workflow that contains a host when a critical detection fires."
    )
    assert result["redirect"] is True


def test_on_demand_block_ip_playbook_redirects():
    result = detect.classify(
        "Create an on-demand playbook to block an IP address given a device ID."
    )
    assert result["redirect"] is True


def test_notification_automation_redirects():
    result = detect.classify(
        "Automate sending a Slack notification when a detection is created."
    )
    assert result["redirect"] is True


def test_scheduled_fusion_soar_workflow_redirects():
    result = detect.classify(
        "I need a Fusion SOAR workflow that runs every 6 hours to tag stale hosts."
    )
    assert result["redirect"] is True


# ── Foundry apps — should NOT redirect ──────────────────────────────────────


def test_ui_extension_app_stays():
    result = detect.classify(
        "Build a Foundry app with a UI extension on the detection panel."
    )
    assert result["redirect"] is False


def test_api_integration_app_stays():
    result = detect.classify(
        "Create an app that integrates with AbuseIPDB via an API integration."
    )
    assert result["redirect"] is False


def test_function_plus_page_app_stays():
    result = detect.classify(
        "Write a serverless function that enriches a detection, exposed on a page."
    )
    assert result["redirect"] is False


def test_workflow_plus_dashboard_app_stays():
    result = detect.classify(
        "Build a workflow AND a dashboard UI to review containment approvals."
    )
    assert result["redirect"] is False


def test_collection_plus_workflow_app_stays():
    result = detect.classify(
        "Create a collection to store enrichment results and a workflow to fill it."
    )
    assert result["redirect"] is False


# ── Non-workflow requests — should NOT redirect ─────────────────────────────


def test_pure_ui_request_does_not_redirect():
    result = detect.classify("Add a new column to my detections UI page.")
    assert result["redirect"] is False


def test_empty_request_does_not_redirect():
    result = detect.classify("")
    assert result["redirect"] is False


# ── Field-level checks ──────────────────────────────────────────────────────


def test_redirect_target_is_fusion_skills():
    result = detect.classify(
        "Build a workflow to contain a host on detection."
    )
    assert result["target"] == "fusion-skills"


def test_app_shaped_request_target_is_foundry_skills():
    result = detect.classify(
        "Build a Foundry app with a UI extension and a workflow."
    )
    assert result["target"] == "foundry-skills"


def test_non_workflow_is_workflow_false():
    result = detect.classify("Add a bar chart to my dashboard page.")
    assert result["is_workflow"] is False
