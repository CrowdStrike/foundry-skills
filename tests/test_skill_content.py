"""Content evals for Foundry skill documentation.

These tests verify that critical guidance is present in skill files —
acting as regression guards against accidental removal of hard-won lessons.
No network or credentials needed; tests read skill files directly.
"""

import os
import re

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


class TestWorkflowLoopsAndFunctionOutputs:
    """Loop linking, function output paths, and what mock executions can test."""

    SKILL = "skills/workflows-development/SKILL.md"

    def test_loop_must_be_linked_from_previous_action(self):
        """An unlinked loop deploys and never runs."""
        content = _read_skill(self.SKILL)
        assert "must name it in its `next:` list" in content
        assert "deploys but never runs" in content

    def test_function_output_path(self):
        """Function outputs live under `.FaaS.<function>.<handler>`, loop items under `.#.`."""
        content = _read_skill(self.SKILL)
        assert "${data['action_key.FaaS.<function>.<handler>.<field>']}" in content
        assert "...<field>.#.<item field>" in content

    def test_mock_executions_do_not_resolve_app_references(self):
        """`executions start` fails app function actions with `action not found`."""
        ref = _read_skill("skills/workflows-development/references/advanced-patterns.md")
        assert "always runs a mock execution" in ref
        assert "error code 1202: action not found" in ref


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
        assert "action:collections.<collection_name>.<Operation>" in content
        assert "action:mcp/gce/collections:collections:generic:<Operation>" in content
        # API-integration tools are referenced by platform tool ID; a
        # name-based alias fails the whole deploy with a bare 500.
        assert "action:mcp/gce/integration:<integration id>~<hash>" in content
        assert "api_integrations.<name>.<agent_tools.name>" not in content
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
        assert "move the inline schema into" in _read_skill(self.SCHEMA)

    def test_workflow_callable_agent_needs_system_action(self):
        """An agent with no exposure flag cannot be called by its own app's workflows.

        Agents read "no flag" as "internal to the app" and fell back to a generic
        LLM action with the prompt copied inline.
        """
        content = _read_skill(self.SKILL)
        assert "No flag means unreachable, even by your own app" in content
        assert "--expose-workflow-system-action` alone" in content

    def test_app_workflow_calls_agent_by_alias(self):
        """An app's workflow references its own agent as `ai_agents.<agent name>`.

        Without this, agents guessed `agents.<name>`, hardcoded the per-CID action ID,
        or fell back to an inline LLM Completion action.
        """
        skill = _read_skill(self.SKILL)
        assert "`ai_agents.<agent name>`" in skill
        assert "references/workflow-invocation.md" in skill
        ref = _read_skill("skills/ai-agents-development/references/workflow-invocation.md")
        assert "id: ai_agents.Triage Agent" in ref
        assert "input: ${data['alert_summary']}" in ref
        assert "version_constraint: ~1" in ref
        assert "version_constraint: ~0" not in ref
        assert "(2018) Action was not found" in ref
        assert "text_data: ${data['run_triage_agent.response']}" in ref
        assert "is not exposed to workflows; set exposure.workflows.system_action to true" in ref
        assert "could not be found" in ref
        assert "invoke_published_agent_external_v1" in ref
        assert "Don't substitute `Charlotte AI - LLM Completion`" in ref
        workflows = _read_skill("skills/workflows-development/SKILL.md")
        assert "id: ai_agents.<agent name>" in workflows
        assert "`version_constraint: ~1`" in workflows
        assert "${data['action_key.response']}" in workflows
        assert "`ai-agents-development` skill's `references/workflow-invocation.md`" in workflows

    def test_json_with_schema_agent_exposes_schema_fields(self):
        """A json_with_schema agent's workflow action has no `response` output.

        Without this, workflows read `.response` from a structured-output agent, which deploys
        and then fails the app install with no detail.
        """
        ref = _read_skill("skills/ai-agents-development/references/workflow-invocation.md")
        assert "A `json_with_schema` agent has no `response` output." in ref
        assert "${data['<action key>.category']}" in ref
        assert "**Install failed**" in ref
        assert "**Settings update failed**" in ref
        assert "**Workflow data** panel" in ref
        workflows = _read_skill("skills/workflows-development/SKILL.md")
        assert "${data['action_key.<schema field>']}" in workflows

    def test_tools_need_the_action_prefix(self):
        """App collection tools deploy only as action:<alias>; unprefixed, deploy returns a bare 500."""
        content = _read_skill(self.SKILL)
        assert "Manifest tools don't deploy yet" not in content
        assert "- action:collections.triage_notes.CreateObject" in content
        assert "Any other form fails the whole deploy, usually with a bare `500`" in content
        ref = _read_skill("skills/ai-agents-development/references/manifest-schema.md")
        assert "### Tool reference format" in ref
        assert "500 Internal Server Error" in ref
        assert "ARTIFACT_DISTRIBUTION_FAILED" in ref
        assert "failed to validate tool used" in ref
        assert "category:'integrations'" in ref, "must say how to look up an API-integration tool ID"
        for skill in ("skills/collections-development/SKILL.md",
                      "skills/ai-agents-development/references/manifest-schema.md"):
            assert "            - collections." not in _read_skill(skill), \
                f"{skill} shows an unprefixed collection tool, which fails deploy"

    def test_api_integration_tools_use_the_platform_tool_id(self):
        """Only the platform tool ID deploys, and it exists only after a first deploy."""
        api = _read_skill("skills/api-integrations/SKILL.md")
        assert "action:mcp/gce/integration:<integration id>~<hash>" in api
        assert "deploy first, look the ID up" in api
        assert "            - api_integrations." not in api

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

    def test_api_tools_ref_is_not_a_name_based_alias(self):
        """A name-based API-integration tools entry fails deploy, so the skill warns against one."""
        content = _read_skill(self.API)
        assert "fails the whole app's deploy with a bare `500`" in content

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


# ── FalconPy Alerts.get_alerts_v2 keyword ───────────────────────────────────


class TestGetAlertsV2Keyword:
    """get_alerts_v2 builds its body from composite_ids only.

    FalconPy rejects ids= for this method with a 400 before sending the
    request, so every example must pass composite_ids. Mocked tests hide the
    difference unless they assert the call's arguments.
    """

    def test_no_example_passes_ids(self):
        offenders = []
        for dirpath, _, files in os.walk(os.path.join(_ROOT, "skills")):
            for name in files:
                if not name.endswith(".md"):
                    continue
                path = os.path.join(dirpath, name)
                with open(path) as f:
                    for lineno, line in enumerate(f, 1):
                        if "get_alerts_v2(ids=" in line:
                            offenders.append(f"{os.path.relpath(path, _ROOT)}:{lineno}")
        assert not offenders, f"get_alerts_v2 must use composite_ids=: {offenders}"

    def test_mock_example_asserts_composite_ids(self):
        content = _read_skill("skills/functions-falcon-api/SKILL.md")
        assert "get_alerts_v2.assert_called_once_with(composite_ids=" in content


# ── Skill links stay inside the skill package ───────────────────────────────


class TestSkillLinksStayInPackage:
    """Every SKILL.md link must resolve inside its own skill directory.

    Assistants other than Claude Code install each skill as its own package,
    and awesome-copilot's valid-refs check rejects links that leave the skill
    directory (outside-skill-dir). Name a sibling skill in prose instead.
    """

    _LINK = re.compile(r"\]\(([^)\s]+)\)")

    def test_no_links_outside_skill_dir(self):
        offenders = []
        skills_dir = os.path.join(_ROOT, "skills")
        for skill in sorted(os.listdir(skills_dir)):
            skill_dir = os.path.join(skills_dir, skill)
            path = os.path.join(skill_dir, "SKILL.md")
            if not os.path.isfile(path):
                continue
            with open(path) as f:
                for lineno, line in enumerate(f, 1):
                    for target in self._LINK.findall(line):
                        if re.match(r"[a-z]+:|#", target):
                            continue
                        resolved = os.path.normpath(
                            os.path.join(skill_dir, target.split("#")[0].split("?")[0])
                        )
                        if os.path.commonpath([resolved, skill_dir]) != skill_dir:
                            offenders.append(f"skills/{skill}/SKILL.md:{lineno} -> {target}")
        assert not offenders, f"links leave the skill directory: {offenders}"

    def test_link_targets_exist(self):
        offenders = []
        skills_dir = os.path.join(_ROOT, "skills")
        for skill in sorted(os.listdir(skills_dir)):
            skill_dir = os.path.join(skills_dir, skill)
            path = os.path.join(skill_dir, "SKILL.md")
            if not os.path.isfile(path):
                continue
            with open(path) as f:
                for lineno, line in enumerate(f, 1):
                    for target in self._LINK.findall(line):
                        if re.match(r"[a-z]+:|#", target):
                            continue
                        resolved = os.path.join(skill_dir, target.split("#")[0].split("?")[0])
                        if not os.path.exists(resolved):
                            offenders.append(f"skills/{skill}/SKILL.md:{lineno} -> {target}")
        assert not offenders, f"links point at missing files: {offenders}"


# ── Lessons from a live Next-Gen SIEM app ───────────────────────────────────


class TestFunctionErrorText:
    """Handlers must pass the Falcon API's error back, not a generic message.

    The rule lived only in the code review checklist, and a generated
    host-lookup handler logged the API error but returned "failed to query
    devices". The SKILL.md body is what an agent reads while writing a handler.
    """

    SKILL = "skills/functions-development/SKILL.md"

    def test_skill_body_says_to_return_the_platform_error(self):
        content = _read_skill(self.SKILL)
        assert "When a Falcon API call fails, return its status and `errors[].message`" in content

    def test_skill_body_says_to_ignore_pycache(self):
        """A local handler run leaves .pyc files that the deploy otherwise packages."""
        content = _read_skill(self.SKILL)
        assert "`(^|/)__pycache__(/|$)`" in content


class TestLiveAppLessons:
    """Verify facts from a live app build that the CLI and API don't explain.

    Each one cost a misdiagnosis: a knowledge base edit that fails the deploy,
    a scope name the CLI rejects, a 404 read as a permission problem, and a
    dashboard API that takes its name from the template, not the parameter.
    """

    KB = "skills/ai-agents-development/references/knowledge-bases.md"
    AGENTS_SKILL = "skills/ai-agents-development/SKILL.md"
    AGENT_REPLY = "skills/ai-agents-development/references/workflow-invocation.md"
    SECURITY = "skills/security-patterns/SKILL.md"
    DEBUG = "skills/debugging-workflows/SKILL.md"
    NGSIEM = "skills/functions-falcon-api/references/ngsiem-content-apis.md"
    FALCON_API = "skills/functions-falcon-api/SKILL.md"
    COLLECTIONS = "skills/collections-development/SKILL.md"
    WORKFLOW = "skills/development-workflow/SKILL.md"

    def test_deployed_kb_files_are_write_once(self):
        content = _read_skill(self.KB)
        assert "write-once" in content
        assert "Dependent artifact failed" in content
        assert "Delete the entry's `id` key" in content
        assert "sanitized new name" in content
        assert "To change a KB's files, delete and re-create it" not in content, \
            "deleting and re-creating doesn't change a deployed KB's files"
        assert "To refresh it you must re-download and overwrite" not in content
        row = next(line for line in _read_skill(self.AGENTS_SKILL).splitlines()
                   if line.startswith("| `file <name> already exists`"))
        assert "409" in row and "knowledge-bases.md" in row, \
            "the deploy 409 shares this text and needs the deployed-KB recovery"

    def test_agent_reply_checked_before_api_calls(self):
        content = _read_skill(self.AGENT_REPLY)
        assert "Acting on an Agent's Reply" in content
        assert "Only the code check stops them" in content

    def test_scopes_add_flag_and_rejected_names(self):
        content = _read_skill(self.SECURITY)
        assert "--scopes" in content
        assert '--scope "devices:read"' not in content, "CLI 2.1.2 has no --scope flag"
        assert 'analyst access" --no-prompt' in content, "roles create needs --no-prompt too"
        assert "major version" in content
        assert "rejects some valid scope names" in content
        assert "`humio-auth-proxy:read`" in content

    def test_manifest_hand_edit_exceptions_agree(self):
        workflow = _read_skill(self.WORKFLOW)
        assert "`auth.scopes` names `scopes add` rejects" in workflow
        assert "renaming a deployed KB" in workflow
        with open(os.path.join(_ROOT, "AGENTS.md")) as f:
            agents_md = f.read()
        assert "one sanctioned reason" not in agents_md
        assert "rename a deployed knowledge base" in agents_md

    def test_identity_and_status_codes(self):
        content = _read_skill(self.DEBUG)
        assert "Which Identity Makes the Call" in content
        assert "for every input" in content
        assert "not a permission problem" in content
        assert "starting an `exec` or `test` run" in content, \
            "a function's FalconPy calls under exec use the installed app's scopes"
        assert "`401 Unauthorized` from FalconPy | Missing OAuth scope" not in content

    def test_no_changes_detected_and_exec_version_pin(self):
        content = _read_skill(self.DEBUG)
        assert "no changes detected" in content
        assert "no app artifacts found of type FAAS_FUNCTION" in content
        assert "--version" in content

    def test_ngsiem_content_api_gotchas(self):
        content = _read_skill(self.NGSIEM)
        assert "Search domain names differ by API" in content
        assert "KeyError: 'name'" in content, "FalconPy 1.6.6 needs name even though the API ignores it"
        assert "queryjobs (`start_search`) is the exception" in content
        assert "such as `falcon`, answers `403`" not in content, \
            "queryjobs answers 404 for falcon, which isn't a view; fusion is the 403 case"
        assert "missing search_domain query param" in content
        assert "maximum supported number of assets already exist in this search domain" in content
        assert "bulk_create_saved_queries_from_template" in content
        assert "ngsiem-persisted-aggregations:read" in content
        assert "ngsiem-lookup-files:write" in content
        assert "ngsiem-*" not in _read_skill(self.FALCON_API), \
            "not a real scope name, and agents copy the scope column"

    def test_collection_writers_merge_or_single_writer(self):
        content = _read_skill(self.COLLECTIONS)
        assert "compare-and-set" in content
        assert "can't give you mutual exclusion" in content
        assert "expired lock as free" not in content, "a lock written with PutObject is its own race"
        assert "reverse-time prefix" not in content, "time-based keys break upsert by natural ID"


class TestPivotAutocomplete:
    """A copied x-cs-pivot ID is rewritten at install, so agents shouldn't "fix" it."""

    REF = "skills/api-integrations/references/spec-adaptation-examples.md"

    def test_pivot_id_and_autocomplete_requirement(self):
        content = _read_skill(self.REF)
        assert "x-cs-pivot" in content
        assert "install rewrites the ID" in content
        assert "not configured for autocomplete" in content


# ── Upgrading template-installed apps (app-upgrades) ────────────────────────


class TestAppUpgrades:
    """Verify the app-upgrades skill documents the in-place upgrade procedure."""

    SKILL = "skills/app-upgrades/SKILL.md"

    def test_syncs_into_scratch_not_working_copy(self):
        content = _read_skill(self.SKILL)
        assert "foundry apps sync --app-id" in content
        assert "-d . " not in content

    def test_every_cli_command_has_no_prompt(self):
        """--no-prompt is required only on sync/validate/deploy/release/delete.

        `foundry apps list` and `list-deployments` have no --no-prompt flag on
        CLI 2.1.2, so checking every `foundry apps` line would fail against
        this skill's own text.
        """
        for line in _read_skill(self.SKILL).splitlines():
            words = line.strip().split()
            if words[:2] == ["foundry", "apps"] and words[2] in (
                "sync", "validate", "deploy", "release", "delete",
            ):
                assert "--no-prompt" in line, line

    def test_deploy_has_change_type_and_log(self):
        deploys = [l for l in _read_skill(self.SKILL).splitlines()
                   if "foundry apps deploy" in l and l.strip().startswith("foundry")]
        assert deploys and all("--change-type" in l and "--change-log" in l for l in deploys)

    def test_confirmation_on_exit_code_2(self):
        content = _read_skill(self.SKILL)
        assert "exit code 2" in content.lower() or "exits 2" in content

    def test_never_strip_ids_to_recover(self):
        assert "creates a second app" in _read_skill(self.SKILL)

    def test_falcon_prefix(self):
        assert "Falcon Foundry" in _read_skill(self.SKILL)


class TestLiveAppLessonsRound2:
    """More facts from live app builds that cost a wrong release or a redesign.

    An unbuilt UI that ships the previous bundle, agent replies thrown away by
    output_format json, agents users can't edit, a workflow flag that was only
    a function input, threads with no token, and integrations with no role check.
    """

    WORKFLOW = "skills/development-workflow/SKILL.md"
    DEPLOY_PATTERNS = "skills/development-workflow/references/advanced-patterns.md"
    AGENT_MANIFEST = "skills/ai-agents-development/references/manifest-schema.md"
    AUTH_EXAMPLES = "skills/api-integrations/references/auth-examples.md"
    AGENTS_SKILL = "skills/ai-agents-development/SKILL.md"
    INVOCATION = "skills/ai-agents-development/references/workflow-invocation.md"
    WF_SKILL = "skills/workflows-development/SKILL.md"
    WF_PATTERNS = "skills/workflows-development/references/advanced-patterns.md"
    WF_EXAMPLES = "skills/workflows-development/references/workflow-examples.md"
    FALCON_API = "skills/functions-falcon-api/SKILL.md"
    FALCON_API_PATTERNS = "skills/functions-falcon-api/references/advanced-patterns.md"
    SECURITY = "skills/security-patterns/SKILL.md"
    INTEGRATIONS = "skills/api-integrations/SKILL.md"

    def test_deploy_does_not_build_ui_and_release_numbering(self):
        content = _read_skill(self.WORKFLOW)
        assert "Deploy never builds a UI" in content
        assert "foundry apps deploy --diff-only --no-prompt" in content
        patterns = _read_skill(self.DEPLOY_PATTERNS)
        assert "ships the previous bundle with no error" in patterns
        assert "a release continues from the last release" in patterns

    def test_json_output_discards_invalid_replies(self):
        assert "drops replies that aren't valid JSON" in _read_skill(self.AGENTS_SKILL)
        content = _read_skill(self.AGENT_MANIFEST)
        assert "output_format_error" in content
        assert "use `output_format: text`, ask for JSON in the system prompt" in content

    def test_app_created_agents_are_app_owned(self):
        assert "agents the app creates are app-owned" in _read_skill(self.AGENTS_SKILL)
        content = _read_skill(self.AGENT_MANIFEST)
        assert "### Who owns an agent" in content
        assert "customer-supplied API client through an API integration" in content

    def test_invocation_default_duration_matches_cli(self):
        content = _read_skill(self.INVOCATION)
        assert "the default is 30 and the maximum 900" in content, "foundry functions create --help: default 30"
        assert "gateway `500`" in content

    def test_continue_on_error_replaces_fail_fast_enabled(self):
        for path in (self.WF_SKILL, self.WF_PATTERNS, self.WF_EXAMPLES):
            content = _read_skill(path)
            assert "fail_fast_enabled: false" not in content, \
                f"{path}: fail_fast_enabled is a function input, not a workflow flag"
        patterns = _read_skill(self.WF_PATTERNS)
        assert "continue_on_error: true" in patterns
        assert "ErrorCode`, `ErrorType`, `HandledBy`, `Message`, and `SourceNodeID`" in patterns
        assert "validate_only` import both accept unknown action keys and broken CEL" in patterns
        assert "continue_on_error: true" in _read_skill(self.WF_SKILL)

    def test_threads_shared_cid_and_workflows_api(self):
        patterns = _read_skill(self.FALCON_API_PATTERNS)
        assert "contextvars.copy_context().run" in patterns
        assert "## Listing on a Shared CID" in patterns
        assert "never use a first call's total as the loop bound" in patterns
        assert "unsupported workflow artifact operation" in patterns
        assert "worker threads" in _read_skill(self.FALCON_API)

    def test_integration_role_gap_and_install_form(self):
        assert "An API integration has no role check, so gate the page that calls it" in _read_skill(self.SECURITY)
        content = _read_skill(self.INTEGRATIONS)
        assert "Put setup steps in `info.description`" in content
        assert "stray `[object Object]` entry" in _read_skill(self.AUTH_EXAMPLES)


class TestUiPlatformFacts:
    """Facts checked in a deployed Foundry page (falcon-shoelace 0.4.0, US-2, 2026-10-23).

    The default CSP allows the jsdelivr CDN and data: URLs, local SVG icons can't
    ship, falcon-shoelace has no tag or badge styles and one stylesheet, and the
    console theme arrives as theme-light/theme-dark on <html>.
    """

    UI = "skills/ui-development"

    def _all(self):
        root = os.path.join(_ROOT, self.UI)
        out = {}
        for dirpath, _, files in os.walk(root):
            for name in files:
                if name.endswith(".md"):
                    rel = os.path.relpath(os.path.join(dirpath, name), _ROOT)
                    out[rel] = _read_skill(rel)
        return out

    def test_no_badge_or_tag_in_examples(self):
        for path, content in self._all().items():
            for bad in ("<sl-badge", "<SlBadge", "<sl-tag", "<SlTag"):
                assert bad not in content, f"{path}: falcon-shoelace doesn't style {bad}"

    def test_falcon_shoelace_has_no_themes_folder(self):
        for path, content in self._all().items():
            assert "falcon-shoelace/dist/themes/" not in content, f"{path}: only dist/style.css exists"

    def test_theme_comes_from_console_not_os(self):
        theming = _read_skill(f"{self.UI}/references/falcon-theming.md")
        assert "classList.toggle('sl-theme-dark'" not in theming
        assert "never reads `sl-theme-*` classes" in theming

    def test_icon_csp_facts(self):
        theming = _read_skill(f"{self.UI}/references/falcon-theming.md")
        assert "already allows `https://cdn.jsdelivr.net` and `data:`" in theming
        assert "Don't serve icons from the app's own package" in theming
        assert "copy icon assets to your `dist/`" not in _read_skill(f"{self.UI}/SKILL.md")

    def test_shoelace_quirks(self):
        ref = _read_skill(f"{self.UI}/references/shoelace-reference.md")
        assert "Option values cannot include a space" in ref
        assert "two tab stops" in ref
        assert "`sl-radio[checked]` selector matches nothing" in ref
        assert "if (e.target === e.currentTarget) setOpen(false)" in ref
        assert "Without these overrides, dialogs appear with a white background" not in ref


class TestScopeTableCasesAndRtr:
    """Cases and RTR scopes, from the API swagger and the RTR role table.

    An eval app called get_cases with only alerts:read, and a judge claimed
    runscript needs the admin API, which Active Responder covers.
    """

    SKILL = "skills/functions-falcon-api/SKILL.md"

    def test_cases_and_rtr_rows(self):
        content = _read_skill(self.SKILL)
        assert "| `CaseManagement` |" in content
        assert "`cases:read` / `cases:write`" in content
        assert "`batch_active_responder_command` (incl. `runscript`)" in content
        assert "`real-time-response-admin:write`" in content


class TestRbacWiring:
    """RBAC examples an agent copies into manifest.yml must match the real format.

    ui.pages is a map keyed by page ID and navigation links point at pages with
    ref:, and permissions create rejects keys without a colon and descriptions
    over 50 characters (CLI 2.1.2).
    """

    SKILL = "skills/security-patterns/SKILL.md"
    EXAMPLES = "skills/security-patterns/references/security-examples.md"

    def test_page_gates_use_the_manifest_map_form(self):
        for path in (self.SKILL, self.EXAMPLES):
            content = _read_skill(path)
            assert "ref: pages.dashboard" in content, path
            assert "  pages:\n    - name:" not in content, f"{path}: ui.pages is a map, not a list"

    def test_permissions_create_limits_quote_the_cli(self):
        content = _read_skill(self.SKILL)
        assert "should be permission segments separated by :" in content
        assert "input must be at most 50 characters long" in content

    def test_rollback_keeps_deploy_written_ids(self):
        for path in (self.SKILL, self.EXAMPLES):
            assert "Do NOT `git checkout manifest.yml`" in _read_skill(path), path
