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

    def test_start_search_uses_search_keyword(self):
        """start_search must be called with search=, never body=.

        FalconPy's guard reads only kwargs["search"], so a body= call returns a
        locally-generated error and never issues a request. See falconpy#1491.
        """
        content = _read_skill(self.SKILL)
        assert "start_search(repository=REPO, search=" in content, \
            "start_search must be called with search=, not body="
        assert "start_search(repository=REPO, body=" not in content, \
            "body= never reaches the API — see falconpy#1491"

    def test_start_search_reads_resources_key(self):
        """The job id must be read from 'resources', not 'body'.

        start_search renames its success payload to 'resources';
        get_search_status does not. Reading 'body' yields None every time.
        """
        content = _read_skill(self.SKILL)
        assert 'started.get("resources")' in content, \
            "job id must be read from the resources key"
        assert 'started.get("body")' not in content, \
            "start_search renames body -> resources on success"

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
        schema_section_start = content.find("## Function I/O Schemas")
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


# ── AI agents and knowledge bases (ai-agents-development) ───────────────────


class TestAIAgentsSkill:
    """Verify the AI skill keeps the facts that cost a round trip to rediscover.

    Every assertion here maps to something the CLI does NOT tell you clearly:
    a name length floor that rejects the obvious short names, a build order
    enforced only at manifest-save time, three fields with no CLI flag at all,
    and a --system-prompt that turns a typo into the agent's instructions.
    """

    SKILL = "skills/ai-agents-development/SKILL.md"
    SCHEMA = "skills/ai-agents-development/references/manifest-schema.md"
    KB = "skills/ai-agents-development/references/knowledge-bases.md"

    def test_manifest_path_is_nested_under_ai(self):
        """Agents live at ai.agents, NOT a top-level agents: key.

        The untracked manifest-specification.md in foundrycli documents a
        top-level `agents:` key, which does not match the Go structs. An early
        draft sourced from that doc and produced manifests the CLI rejects.
        """
        content = _read_skill(self.SKILL)
        assert "ai:" in content
        assert "knowledge_bases:" in content, "manifest key is knowledge_bases (underscore)"
        # The on-disk directory is hyphenated while the manifest key is not —
        # getting these backwards is the single easiest mistake to make here.
        assert "knowledge-bases/" in content, "on-disk dir is knowledge-bases (hyphen)"

    def test_build_order_kb_before_agent(self):
        """Must state knowledge bases come first, and name the error if not."""
        content = _read_skill(self.SKILL)
        assert "Build Order Is Mandatory" in content
        assert "which is not defined in the manifest" in content, \
            "must quote the actual failure so it is recognizable"

    def test_name_minimum_length_documented(self):
        """5-char name floor rejects 'kb' and 'agent' — the obvious names."""
        content = _read_skill(self.SKILL)
        assert "5–100" in content or "5-100" in content
        assert "`kb`" in content, "must call out that short names fail"

    def test_kb_validation_asymmetry_documented(self):
        """kb create enforces 5 chars; the manifest validator only needs 1.

        The manifest validators were deliberately relaxed (the AI platform has no
        name restriction) while the create flags were left strict. Documenting
        only one half sends a reader in circles over an inherited manifest.
        """
        content = _read_skill(self.SKILL)
        assert "asymmetry" in content.lower()
        assert "1 character" in content or "one character" in content or "only requires 1" in content

    def test_cli_unsettable_fields_documented(self):
        """model and tools have no CLI flags. Exposure does — it is not in this set."""
        content = _read_skill(self.SKILL)
        assert "Two Fields the CLI Cannot Set" in content
        for field in ("model", "tools"):
            assert f"`{field}`" in content
        assert "Three Fields the CLI Cannot Set" not in content, \
            "exposure gained --expose-* flags; it is no longer hand-edit-only"

    def test_exposure_flags_documented(self):
        """All three --expose-* flags, with the agent_as_tool schema pairing."""
        content = _read_skill(self.SKILL)
        for flag in ("--expose-charlotte-chat", "--expose-agent-as-tool",
                     "--expose-workflow-system-action"):
            assert flag in content, f"missing exposure flag {flag}"
        assert "--input-schema is required when --expose-agent-as-tool is set" in content, \
            "must quote the create-time failure"
        assert "input_schema is required when exposure.agent_as_tool is true" in content, \
            "must quote the manifest-load failure — it breaks every later CLI call"

    def test_exposure_block_omitted_when_unused(self):
        """An absent exposure block is correct, not a missing default.

        Earlier CLI builds always wrote the block with every switch false. It is
        now a pointer with omitempty, so a reader who expects the old shape will
        try to 'repair' a correct manifest.
        """
        content = _read_skill(self.SKILL)
        assert "omitted entirely when nothing is exposed" in content

    def test_delete_commands_documented(self):
        """delete exists for both artifacts and behaves like every other command."""
        content = _read_skill(self.SKILL)
        assert "foundry agents delete" in content
        assert "foundry knowledge-bases delete" in content
        assert "still referenced by agent(s)" in content, \
            "KB deletion is blocked while an agent references it"
        assert "no `list` or `edit`" in content

    def test_delete_takes_no_prompt_like_everything_else(self):
        """delete accepts --no-prompt — do not reintroduce the old exception.

        An earlier CLI build registered these two commands without the flag, so
        passing it failed with 'unknown flag'. That was reverted for consistency
        An earlier CLI build registered these two commands without the flag, so
        passing it failed with 'unknown flag'. That was reverted for consistency.
        Carrying the exception in the docs would send readers to
        Carrying the exception in the docs would send readers to
        strip a flag the CLI now needs.
        """
        for path in (self.SKILL, self.SCHEMA, self.KB):
            content = _read_skill(path)
            assert "unknown flag: --no-prompt" not in content, \
                f"{path} still documents the reverted --no-prompt exception"
        skill = _read_skill(self.SKILL)
        assert "foundry agents delete --name \"Detection Triage Agent\" --no-prompt" in skill, \
            "the delete example must carry --no-prompt like every other command"

    def test_manifest_edit_carve_out_is_scoped(self):
        """The exception to 'never edit manifest.yml' must be explicitly narrow.

        A blanket "editing the manifest is fine here" would erode the rule that
        protects id/path/entrypoint across every other capability.
        """
        content = _read_skill(self.SKILL)
        assert "narrow, explicit exception" in content
        assert "id" in content and "path" in content

    def test_model_left_empty_not_invented(self):
        """No invented model IDs — there is no client-side list."""
        content = _read_skill(self.SKILL)
        assert 'model: ""' in content
        assert "platform default" in content.lower()

    def test_tools_reference_formats(self):
        """All three tools reference shapes, with exact operation casing."""
        content = _read_skill(self.SKILL)
        assert "collections.<collection_name>.<Operation>" in content
        assert "collections.generic.<Operation>" in content
        # Final segment is agent_tools.name, NOT the operationId — sending a
        # reader to the operationId yields a silent tool-reference failure.
        assert "api_integrations.<name>.<agent_tools.name>" in content
        assert "api_integrations.<name>.<operationId>" not in content
        for op in ("CreateObject", "GetObject", "DeleteObject",
                   "ListObjects", "SearchObjects"):
            assert op in content, f"missing collection operation {op}"

    def test_system_prompt_fallback_trap(self):
        """A typo'd --system-prompt path silently becomes the prompt text."""
        content = _read_skill(self.SKILL)
        assert "inline text" in content
        assert "system_prompt.txt" in content

    def test_output_schema_only_for_json_with_schema(self):
        """json needs no schema; only json_with_schema does."""
        content = _read_skill(self.SKILL)
        assert "json_with_schema" in content
        assert "asymmetry" in content.lower()

    def test_schema_filenames_are_fixed(self):
        """The backend reads only input_schema.json / output_schema.json.

        Any other name deploys with no schema (older CLIs) or fails every
        manifest load (newer CLIs), so the naming rule and both error strings
        must stay documented.
        """
        content = _read_skill(self.SKILL)
        assert "input_schema.json" in content
        assert "output_schema.json" in content
        assert "output schema is required when using JSON format" in content
        assert 'output_schema must be "output_schema.json"' in content
        assert "inline schemas are not read" in _read_skill(self.SCHEMA)

    def test_workflow_callable_agent_needs_system_action(self):
        """An agent with no exposure flag cannot be called by its own app's workflows.

        Agents read "no flag" as "internal to the app" and fell back to a generic
        LLM action with the prompt copied inline.
        """
        content = _read_skill(self.SKILL)
        assert "No flag means unreachable, even by your own app" in content
        assert "--expose-workflow-system-action` alone" in content

    def test_no_invented_tuning_knobs(self):
        """No temperature, chunk size, similarity, or top_k keys exist to set."""
        content = _read_skill(self.SKILL)
        assert "No other tuning knobs exist" in content
        for knob in ("temperature", "chunk size", "similarity", "`top_k`"):
            assert knob in content, f"must name the nonexistent {knob} knob"

    def test_kb_reference_covers_svg_drop(self):
        """.svg KB files pass validation then vanish from the deploy bundle."""
        content = _read_skill(self.KB)
        assert ".svg" in content
        assert "25 MB" in content

    def test_schema_reference_has_no_version_gate_claim(self):
        """Must state there is no manifest_version gate for ai artifacts."""
        content = _read_skill(self.SCHEMA)
        assert "2023-05-09" in content
        assert "no `manifest_version` gate" in content


# ── Agent tool exposure is documented on both sides ──────────────────────────


class TestAgentToolExposure:
    """Exposure and the tools entry are both required; neither alone errors.

    The two halves live in different skills, so a reader who loads only one
    must still learn that the other half exists.
    """

    COLLECTIONS = "skills/collections-development/SKILL.md"
    API = "skills/api-integrations/SKILL.md"
    AI = "skills/ai-agents-development/SKILL.md"

    def test_collections_documents_the_flag_and_block(self):
        content = _read_skill(self.COLLECTIONS)
        assert "--agent-tools-expose" in content
        assert "agent_tools_integration" in content

    def test_api_integrations_documents_nested_agent_tools(self):
        """expose_to_agent must be nested under agent_tools, like the workflow key."""
        content = _read_skill(self.API)
        assert "agent_tools" in content
        assert "expose_to_agent" in content

    def test_api_tools_ref_uses_agent_tools_name_not_operation_id(self):
        """The last segment is agent_tools.name, not the operationId."""
        content = _read_skill(self.API)
        assert "api_integrations." in content
        assert "not the `operationId`" in content

    def test_both_halves_required_is_stated_in_all_three(self):
        """Every skill that mentions exposure must warn it is only half."""
        for skill in (self.COLLECTIONS, self.API, self.AI):
            content = _read_skill(skill)
            assert "silently cannot" in content, \
                f"{skill} must warn that exposure alone is insufficient"


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
