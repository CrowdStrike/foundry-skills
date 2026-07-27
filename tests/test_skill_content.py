"""Content evals for Foundry skill documentation.

These tests verify that critical guidance is present in skill files —
acting as regression guards against accidental removal of hard-won lessons.
No network or credentials needed; tests read skill files directly.
"""

import os

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _read_skill(relative_path: str) -> str:
    """Read a skill file and return its content as a string."""
    path = os.path.join(_ROOT, relative_path)
    with open(path) as f:
        return f.read()


# ── LogScale/NGSIEM query recipe (functions-falcon-api) ─────────────────────


class TestNGSIEMQueryRecipe:
    """Verify the NGSIEM query recipe covers Jeevan's Problem 1 and 2."""

    SKILL = "skills/functions-falcon-api/SKILL.md"

    def test_class_disambiguation_present(self):
        """Must state which class to use for querying vs ingestion."""
        content = _read_skill(self.SKILL)
        # Anchor on the disambiguation callout, not the bare class names —
        # both appear in the scope table on main.
        assert "Class Disambiguation" in content
        assert "ingest_data" in content, "must name FoundryLogScale's ingestion method"

    def test_search_all_repository_documented(self):
        """Must document 'search-all' as the required repository value."""
        content = _read_skill(self.SKILL)
        assert "search-all" in content
        # Must explain that specific repo names cause 403
        assert "403" in content

    def test_start_search_method_shown(self):
        """Must show the NGSIEM start_search method."""
        content = _read_skill(self.SKILL)
        assert "start_search" in content
        assert "get_search_status" in content
        # Must use the NGSIEM class, not FoundryLogScale, for searching
        assert "ngsiem.start_search" in content.lower() or \
               "NGSIEM()" in content

    def test_query_scope_documented(self):
        """Must document humio-auth-proxy:read for queries."""
        content = _read_skill(self.SKILL)
        assert "humio-auth-proxy:read" in content

    def test_repo_filter_in_query_string(self):
        """Must show how to filter to a specific repo within the query string."""
        content = _read_skill(self.SKILL)
        assert "#repo=" in content

    def test_blog_reference_included(self):
        """Must link to the Tech Hub blog post as reference."""
        content = _read_skill(self.SKILL)
        assert "exporting-falcon-next-gen-siem-query-results-to-csv" in content


# ── Function I/O schema requirements (functions-development) ────────────────


class TestFunctionSchemaRequirements:
    """Verify function schema guidance covers Jeevan's Problem 3."""

    SKILL = "skills/functions-development/SKILL.md"

    def test_output_schema_requirement_documented(self):
        """Must state output schema is required at creation time."""
        content = _read_skill(self.SKILL)
        assert "Function I/O Schemas" in content
        assert "--output-schema" in content

    def test_missing_schema_consequence_explained(self):
        """Must explain what happens without an output schema."""
        content = _read_skill(self.SKILL)
        assert "no visible output" in content or "zero output" in content

    def test_uses_real_manifest_field_names(self):
        """Must use the field names the CLI actually writes.

        The CLI records schemas as request_schema/response_schema on the
        handler. An earlier draft used input_schema/output_schema nested under
        workflow_integration, which does not exist in a real manifest.
        """
        content = _read_skill(self.SKILL)
        assert "request_schema" in content
        assert "response_schema" in content

    def test_wf_expose_alone_is_insufficient(self):
        """Must warn that --wf-expose does not generate schemas."""
        content = _read_skill(self.SKILL)
        assert "--wf-expose" in content
        assert "null" in content, "must state schema fields are null without the flags"

    def test_does_not_claim_manifest_edit_binds_schemas(self):
        """Must state that hand-editing the manifest does not bind schemas."""
        content = _read_skill(self.SKILL)
        schema_section_start = content.find("Function I/O Schemas")
        assert schema_section_start != -1
        schema_section = content[schema_section_start:schema_section_start + 3000]
        assert "does NOT bind" in schema_section or "does not bind" in schema_section.lower()

    def test_creation_time_requirement_emphasized(self):
        """Must show both CLI schema flags."""
        content = _read_skill(self.SKILL)
        assert "--input-schema" in content and "--output-schema" in content


# ── Workflow deletion warning (workflows-development) ───────────────────────


class TestWorkflowDeletionWarning:
    """Verify workflow deletion danger covers Jeevan's Problem 4."""

    SKILL = "skills/workflows-development/SKILL.md"

    def test_deletion_warning_present(self):
        """Must have a dedicated warning about workflow deletion dangers."""
        content = _read_skill(self.SKILL)
        assert "NEVER Delete and Recreate Workflows" in content or \
               "NEVER delete and recreate" in content.lower()

    def test_duplicate_name_trap_documented(self):
        """Must explain the 'duplicate name' / 409 error that results."""
        content = _read_skill(self.SKILL)
        assert "409" in content or "duplicate name" in content.lower() or \
               "name must be unique" in content

    def test_recovery_cost_explained(self):
        """Must explain that recovery often requires a fresh app."""
        content = _read_skill(self.SKILL)
        assert "fresh app" in content or \
               "delete the entire app" in content or \
               "deleting the entire app" in content

    def test_dependent_artifact_error_documented(self):
        """Must document the cascading 'dependent artifact failed' error."""
        content = _read_skill(self.SKILL)
        assert "dependent artifact" in content

    def test_alternatives_provided(self):
        """Must direct the reader to update in place rather than recreate."""
        content = _read_skill(self.SKILL)
        # Anchor on the specific instruction — "edit"/"deploy" appear all over
        # this file for unrelated reasons and pass even without the warning.
        assert "update in place" in content.lower()

    def test_old_delete_advice_removed(self):
        """Must NOT advise 'delete and re-create' as a fix for missing workflow_integration."""
        content = _read_skill(self.SKILL)
        # The old advice was exactly this sentence:
        assert "delete and re-create it with the appropriate flags" not in content


# ── Cross-skill consistency ─────────────────────────────────────────────────


class TestCrossSkillConsistency:
    """Guard against the two skills giving opposite advice for one task.

    An earlier draft of this branch had workflows-development saying to fix a
    missing workflow_integration by editing the manifest and redeploying, while
    functions-development said to recreate the function. Both load together for
    workflow+function apps, so the contradiction was reachable.
    """

    FUNCTIONS = "skills/functions-development/SKILL.md"
    WORKFLOWS = "skills/workflows-development/SKILL.md"

    def test_neither_skill_claims_manifest_edit_adds_workflow_integration(self):
        """Both skills must agree that recreation, not a manifest edit, is the fix."""
        workflows = _read_skill(self.WORKFLOWS)
        assert "add the `workflow_integration` block to the function's manifest entry and redeploy" \
            not in workflows

    def test_both_skills_point_at_creation_time_binding(self):
        """Both must name the CLI flags as the binding mechanism."""
        for skill in (self.FUNCTIONS, self.WORKFLOWS):
            content = _read_skill(skill)
            assert "--input-schema" in content or "--wf-expose" in content, \
                f"{skill} should reference the creation-time flags"
