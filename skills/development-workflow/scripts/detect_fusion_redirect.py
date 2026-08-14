#!/usr/bin/env python3
"""Classify whether a request is a standalone Fusion workflow (redirect to
the crowdstrike-falcon-fusion plugin) or a Falcon Foundry app (handle here).

A standalone Fusion workflow needs only a trigger plus actions that already
exist in the CID — no UI, no serverless function, no collection, no custom API
integration to be built, no manifest.yml. Those app-only capabilities are what
keep a request in foundry-skills. When none are present, the request belongs to
the sibling crowdstrike-falcon-fusion plugin.

This is a heuristic used to *advise* a redirect; it never blocks. The routing
decision ultimately rests with the orchestrator skill (development-workflow),
which reads the same signals described here.

Usage:
    detect_fusion_redirect.py "build a workflow that contains a host on detection"
    echo "<request>" | detect_fusion_redirect.py
Exit code 0 always (advisory). Prints a JSON verdict.
"""

import json
import re
import sys

# Signals that a request needs a Foundry APP (keep it in foundry-skills). If any
# of these are present, do NOT redirect — the request needs app scaffolding.
APP_CAPABILITY_PATTERNS = (
    r"\bUI\b",
    r"\buser interface\b",
    r"\bdashboard\b",
    r"\bextension\b",
    r"\bpage\b",
    r"\bpanel\b",
    r"\bwidget\b",
    r"\bfunction\b",
    r"\bserverless\b",
    r"\blambda\b",
    r"\bcollection\b",
    r"\bmanifest\b",
    r"\bFoundry app\b",
    r"\bAPI integration\b",
    r"\bintegrate with\b",
    r"\bOpenAPI\b",
    r"\bcustom (SOAR )?action\b",
)

# Signals that a request is about a workflow / automation at all. Without one of
# these, the request isn't a workflow request and this classifier abstains.
WORKFLOW_PATTERNS = (
    r"\bworkflow\b",
    r"\bplaybook\b",
    r"\bautomation\b",
    r"\bautomate\b",
    r"\bon[- ]demand\b",
    r"\bon detection\b",
    r"\btrigger\b",
    r"\bFusion\b",
    r"\bSOAR\b",
)


def _matches(patterns, text):
    """Return the list of pattern sources that match text (case-insensitive)."""
    hits = []
    for pat in patterns:
        if re.search(pat, text, re.IGNORECASE):
            hits.append(pat)
    return hits


# Negation cues that *withdraw* a capability rather than request it. A prompt
# saying "no UI, no functions" is describing what it does NOT need, so those
# words must not count as app signals — the naive read inverts the verdict and
# keeps a standalone-workflow request in foundry-skills.
_NEGATION_CUE = (
    r"(?:no|not|without|excluding|skip|omit|"
    r"(?:do(?:n't|es not|esn't| not)? (?:need|want|require))|"
    r"(?:no need for)|(?:isn't|is not|aren't|are not))"
)

# A negation scopes over the capabilities that follow it, including across a
# comma/"or"/"and" series: "no UI, no functions" and "without a UI or function".
# Stop at sentence-ending punctuation so a later clause isn't swallowed.
_NEGATED_SPAN = re.compile(
    rf"\b{_NEGATION_CUE}\b[^.;!?\n]*",
    re.IGNORECASE,
)


def _strip_negated_spans(text):
    """Blank out spans where capabilities are explicitly ruled out.

    Replaces with spaces rather than deleting so surrounding word boundaries
    survive and offsets stay comparable.
    """
    return _NEGATED_SPAN.sub(lambda m: " " * len(m.group(0)), text or "")


def classify(request):
    """Classify a natural-language request.

    Returns a dict:
      redirect        - True if it looks like a standalone Fusion workflow
      target          - "crowdstrike-falcon-fusion" when redirecting, else
                        "crowdstrike-falcon-foundry"
      is_workflow     - whether the request mentions a workflow/automation
      app_signals     - app-capability patterns that matched (block redirect)
      reason          - one-line human-readable explanation
    """
    text = request or ""
    workflow_hits = _matches(WORKFLOW_PATTERNS, text)
    # Match app signals only against text with negated spans removed, so
    # "no UI, no functions" reads as an absence of those capabilities.
    affirmative = _strip_negated_spans(text)
    app_hits = _matches(APP_CAPABILITY_PATTERNS, affirmative)
    negated_app_hits = [
        p for p in _matches(APP_CAPABILITY_PATTERNS, text) if p not in app_hits
    ]

    is_workflow = bool(workflow_hits)
    # Redirect only when it's clearly a workflow AND carries no app-only signal.
    redirect = is_workflow and not app_hits

    if not is_workflow:
        reason = "Not a workflow request; no redirect signal."
    elif app_hits:
        reason = (
            "Workflow request also needs a Foundry app capability "
            f"({len(app_hits)} app signal(s)) — handle in foundry-skills."
        )
    else:
        reason = (
            "Standalone Fusion workflow (trigger + existing actions, no app "
            "capability) — advise the crowdstrike-falcon-fusion plugin."
        )

    return {
        "redirect": redirect,
        "target": "crowdstrike-falcon-fusion" if redirect else "crowdstrike-falcon-foundry",
        "is_workflow": is_workflow,
        "app_signals": app_hits,
        "negated_app_signals": negated_app_hits,
        "reason": reason,
    }


def main(argv):
    """CLI entry point. Reads the request from argv or stdin, prints JSON."""
    if len(argv) > 1:
        request = " ".join(argv[1:])
    else:
        request = sys.stdin.read()
    print(json.dumps(classify(request), indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
