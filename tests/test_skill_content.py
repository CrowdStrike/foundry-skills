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
        """Must clarify when to use NGSIEM vs FoundryLogScale."""
        content = _read_skill(self.SKILL)
        assert "NGSIEM" in content
        assert "FoundryLogScale" in content
        # Must explicitly state NGSIEM is for querying
        assert "querying" in content.lower() or "query" in content.lower()

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
        """Must state that output_schema is required at creation time."""
        content = _read_skill(self.SKILL)
        assert "output_schema" in content
        # Must be framed as a requirement, not optional
        assert "MUST" in content or "Required" in content or "CRITICAL" in content

    def test_missing_schema_consequence_explained(self):
        """Must explain what happens without output schema."""
        content = _read_skill(self.SKILL)
        # Must mention that actions show no output
        assert "no visible output" in content or "zero output" in content

    def test_schema_manifest_example_provided(self):
        """Must show a manifest.yml example with workflow_integration schemas."""
        content = _read_skill(self.SKILL)
        assert "workflow_integration" in content
        assert "input_schema" in content
        assert "output_schema" in content

    def test_does_not_recommend_manifest_edit_to_fix_schema(self):
        """Must NOT claim that editing manifest and redeploying binds schemas."""
        content = _read_skill(self.SKILL)
        # Find the schema section and verify it explains schemas can't be added after creation
        schema_section_start = content.find("Function I/O Schemas")
        assert schema_section_start != -1
        schema_section = content[schema_section_start:schema_section_start + 3000]
        assert "does NOT bind" in schema_section or "does not bind" in schema_section.lower()

    def test_creation_time_requirement_emphasized(self):
        """Must state schemas are bound at creation time via CLI flags."""
        content = _read_skill(self.SKILL)
        assert "--input-schema" in content or "--output-schema" in content


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
        """Must provide safe alternatives (update in place, redeploy)."""
        content = _read_skill(self.SKILL)
        assert "update in place" in content.lower() or "edit" in content.lower()
        assert "redeploy" in content or "deploy" in content

    def test_old_delete_advice_removed(self):
        """Must NOT advise 'delete and re-create' as a fix for missing workflow_integration."""
        content = _read_skill(self.SKILL)
        # The old advice was exactly this sentence:
        assert "delete and re-create it with the appropriate flags" not in content
