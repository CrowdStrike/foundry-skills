#!/usr/bin/env python3
"""Tests for detect_fusion_redirect.py"""
# pylint: disable=wrong-import-position,global-statement

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import detect_fusion_redirect as detect

PASS = 0
FAIL = 0


def check(request, expect_redirect, msg):
    """Assert classify(request).redirect matches expect_redirect."""
    global PASS, FAIL
    result = detect.classify(request)
    if result["redirect"] == expect_redirect:
        PASS += 1
        print(f"  PASS: {msg}")
    else:
        FAIL += 1
        print(f"  FAIL: {msg}")
        print(f"    expected redirect={expect_redirect}, got {result['redirect']}")
        print(f"    reason: {result['reason']}")


def check_field(request, field, expected, msg):
    """Assert a specific field of the classification."""
    global PASS, FAIL
    actual = detect.classify(request).get(field)
    if actual == expected:
        PASS += 1
        print(f"  PASS: {msg}")
    else:
        FAIL += 1
        print(f"  FAIL: {msg}")
        print(f"    expected {field}={expected}, got {actual}")


print("Standalone Fusion workflows — SHOULD redirect to fusion-skills:")
check(
    "Build a workflow that contains a host when a critical detection fires.",
    True,
    "contain-host-on-detection workflow",
)
check(
    "Create an on-demand playbook to block an IP address given a device ID.",
    True,
    "on-demand block-IP playbook",
)
check(
    "Automate sending a Slack notification when a detection is created.",
    True,
    "notification automation",
)
check(
    "I need a Fusion SOAR workflow that runs every 6 hours to tag stale hosts.",
    True,
    "scheduled Fusion SOAR workflow",
)

print("\nFoundry apps — should NOT redirect (handle in foundry-skills):")
check(
    "Build a Foundry app with a UI extension on the detection panel.",
    False,
    "UI extension app",
)
check(
    "Create an app that integrates with AbuseIPDB via an API integration.",
    False,
    "API integration app",
)
check(
    "Write a serverless function that enriches a detection, exposed on a page.",
    False,
    "function + page app",
)
check(
    "Build a workflow AND a dashboard UI to review containment approvals.",
    False,
    "workflow + dashboard (app-shaped compound request)",
)
check(
    "Create a collection to store enrichment results and a workflow to fill it.",
    False,
    "collection + workflow app",
)

print("\nNon-workflow requests — should NOT redirect (classifier abstains):")
check(
    "Add a new column to my detections UI page.",
    False,
    "pure UI request, not a workflow",
)
check(
    "",
    False,
    "empty request",
)

print("\nField-level checks:")
check_field(
    "Build a workflow to contain a host on detection.",
    "target",
    "fusion-skills",
    "redirect target is fusion-skills",
)
check_field(
    "Build a Foundry app with a UI extension and a workflow.",
    "target",
    "foundry-skills",
    "app-shaped request stays in foundry-skills",
)
check_field(
    "Add a bar chart to my dashboard page.",
    "is_workflow",
    False,
    "non-workflow request flagged is_workflow=False",
)

print(f"\n{PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
