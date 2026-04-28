#!/usr/bin/env bash
#
# test-hooks.sh — Unit tests for hook scripts
#
# Tests foundry-skill-router.sh (UserPromptSubmit + PreToolUse),
# superpowers-foundry-bridge.sh (Skill interception),
# foundry-cli-guard.sh (--no-prompt enforcement), and
# foundry-session-start.sh (SessionStart version check).
#
# Usage: ./test-hooks.sh
#
set -euo pipefail

PASS=0
FAIL=0
TOTAL=0

HOOK="./hooks/foundry-skill-router.sh"
BRIDGE="./hooks/superpowers-foundry-bridge.sh"
GUARD="./hooks/foundry-cli-guard.sh"
MARKER="/tmp/.foundry-skill-router-active"

GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

# ---------- Helpers ----------

cleanup() {
  rm -f "$MARKER"
  rm -f /tmp/test-spec-*.yaml /tmp/test-spec-*.json
  unset FOUNDRY_SKIP_NAME_CONFIRM 2>/dev/null || true
}

assert_contains() {
  local output="$1" expected="$2" name="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$output" | grep -qF "$expected"; then
    PASS=$((PASS + 1))
    printf "${GREEN}  PASS${RESET} %s\n" "$name"
  else
    FAIL=$((FAIL + 1))
    printf "${RED}  FAIL${RESET} %s\n" "$name"
    printf "       expected to contain: %s\n" "$expected"
    printf "       got: %.200s\n" "$output"
  fi
}

assert_not_contains() {
  local output="$1" unexpected="$2" name="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$output" | grep -qF "$unexpected"; then
    FAIL=$((FAIL + 1))
    printf "${RED}  FAIL${RESET} %s\n" "$name"
    printf "       should NOT contain: %s\n" "$unexpected"
  else
    PASS=$((PASS + 1))
    printf "${GREEN}  PASS${RESET} %s\n" "$name"
  fi
}

assert_empty() {
  local output="$1" name="$2"
  TOTAL=$((TOTAL + 1))
  if [ -z "$output" ]; then
    PASS=$((PASS + 1))
    printf "${GREEN}  PASS${RESET} %s\n" "$name"
  else
    FAIL=$((FAIL + 1))
    printf "${RED}  FAIL${RESET} %s\n" "$name"
    printf "       expected empty output, got: %.200s\n" "$output"
  fi
}

assert_json_field() {
  local output="$1" jq_expr="$2" expected="$3" name="$4"
  TOTAL=$((TOTAL + 1))
  local actual
  actual=$(echo "$output" | jq -r "$jq_expr" 2>/dev/null || echo "__JQ_ERROR__")
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1))
    printf "${GREEN}  PASS${RESET} %s\n" "$name"
  else
    FAIL=$((FAIL + 1))
    printf "${RED}  FAIL${RESET} %s\n" "$name"
    printf "       jq '%s' expected: %s\n" "$jq_expr" "$expected"
    printf "       got: %s\n" "$actual"
  fi
}

assert_marker_exists() {
  local name="$1"
  TOTAL=$((TOTAL + 1))
  if [ -f "$MARKER" ]; then
    PASS=$((PASS + 1))
    printf "${GREEN}  PASS${RESET} %s\n" "$name"
  else
    FAIL=$((FAIL + 1))
    printf "${RED}  FAIL${RESET} %s\n" "$name"
    printf "       marker file not found at %s\n" "$MARKER"
  fi
}

assert_marker_not_exists() {
  local name="$1"
  TOTAL=$((TOTAL + 1))
  if [ ! -f "$MARKER" ]; then
    PASS=$((PASS + 1))
    printf "${GREEN}  PASS${RESET} %s\n" "$name"
  else
    FAIL=$((FAIL + 1))
    printf "${RED}  FAIL${RESET} %s\n" "$name"
    printf "       marker file should not exist at %s\n" "$MARKER"
  fi
}

run_hook() {
  local hook="$1" json="$2"
  echo "$json" | "$hook" 2>/dev/null || true
}

# Run the spec-adaptation hook for a given spec file path.
# Usage: OUTPUT=$(run_spec_hook "/tmp/test-spec-3-1.yaml")
run_spec_hook() {
  local spec_path="$1"
  local json
  json=$(jq -n --arg cmd "foundry api-integrations create --name X --spec $spec_path" \
    '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $cmd}}')
  run_hook "$HOOK" "$json"
}

# ---------- Section 1: UserPromptSubmit — Should Match ----------

printf "\n${BOLD}Section 1: UserPromptSubmit — Should Match${RESET}\n\n"

MATCH_PROMPTS=(
  "create a foundry app for Okta"
  "Build a Falcon Foundry integration"
  "I need to deploy the foundry app"
  "foundry app needs a fix"
  "Can you run foundry apps deploy?"
  "foundry login"
  "use foundry skill"
  "CREATE A FOUNDRY APP"
  "add a foundry workflow and ui page"
  "debug the foundry function error"
)

MATCH_NAMES=(
  "1.1  verb + noun basic case"
  "1.2  different verb + 'falcon foundry'"
  "1.3  verb after non-verb words"
  "1.4  noun-first, verb-second"
  "1.5  explicit CLI command (foundry apps deploy)"
  "1.6  explicit CLI command (foundry login)"
  "1.7  explicit skill request"
  "1.8  uppercase input"
  "1.9  multiple nouns"
  "1.10 debug verb"
)

for i in "${!MATCH_PROMPTS[@]}"; do
  cleanup
  PROMPT="${MATCH_PROMPTS[$i]}"
  JSON=$(jq -n --arg p "$PROMPT" '{hook_event_name: "UserPromptSubmit", prompt: $p}')
  OUTPUT=$(run_hook "$HOOK" "$JSON")

  assert_contains "$OUTPUT" "FOUNDRY PLUGIN DETECTED" "${MATCH_NAMES[$i]}: injects context"
  assert_marker_exists "${MATCH_NAMES[$i]}: creates marker"
done

# ---------- Section 2: UserPromptSubmit — Should NOT Match ----------

printf "\n${BOLD}Section 2: UserPromptSubmit — Should NOT Match${RESET}\n\n"

NO_MATCH_PROMPTS=(
  "the foundry function runs daily"
  "tell me about foundry"
  "what is a foundry app?"
  "create a react application"
  "the building has a foundry"
  "I'm running the tests"
  "foundry is interesting"
)

NO_MATCH_NAMES=(
  "2.1  'runs' not a matching verb"
  "2.2  no action verb (tell me about)"
  "2.3  question, no action verb"
  "2.4  verb but no foundry noun"
  "2.5  'building' as noun, not verb"
  "2.6  no foundry noun"
  "2.7  no action verb (is interesting)"
)

for i in "${!NO_MATCH_PROMPTS[@]}"; do
  cleanup
  PROMPT="${NO_MATCH_PROMPTS[$i]}"
  JSON=$(jq -n --arg p "$PROMPT" '{hook_event_name: "UserPromptSubmit", prompt: $p}')
  OUTPUT=$(run_hook "$HOOK" "$JSON")

  assert_empty "$OUTPUT" "${NO_MATCH_NAMES[$i]}: no output"
  assert_marker_not_exists "${NO_MATCH_NAMES[$i]}: no marker"
done

# ---------- Section 3: PreToolUse — OpenAPI Spec Auto-Adaptation ----------

printf "\n${BOLD}Section 3: PreToolUse — OpenAPI Spec Auto-Adaptation${RESET}\n\n"

# 3.1 — default without enum → auto-fixed by adapt script
cleanup
cat > /tmp/test-spec-3-1.yaml <<'EOF'
openapi: "3.0.0"
info:
  title: Test
  version: "1.0"
servers:
  - url: "{domain}"
    variables:
      domain:
        default: "example.com"
        description: "API domain"
paths: {}
EOF
OUTPUT=$(run_spec_hook "/tmp/test-spec-3-1.yaml")
assert_contains "$OUTPUT" "automatically fixed" "3.1  default without enum → auto-fixed"
assert_contains "$OUTPUT" "Removed default" "3.1  reports default removal"

# 3.2 — default WITH enum → ALLOW (no changes needed)
cleanup
cat > /tmp/test-spec-3-2.yaml <<'EOF'
openapi: "3.0.0"
info:
  title: Test
  version: "1.0"
servers:
  - url: "{domain}"
    variables:
      domain:
        default: "example.com"
        enum:
          - "example.com"
          - "api.example.com"
        description: "API domain"
paths: {}
EOF
OUTPUT=$(run_spec_hook "/tmp/test-spec-3-2.yaml")
assert_empty "$OUTPUT" "3.2  default WITH enum → ALLOW (no changes)"

# 3.3 — description only (no default) → ALLOW
cleanup
cat > /tmp/test-spec-3-3.yaml <<'EOF'
openapi: "3.0.0"
info:
  title: Test
  version: "1.0"
servers:
  - url: "{domain}"
    variables:
      domain:
        description: "API domain"
paths: {}
EOF
OUTPUT=$(run_spec_hook "/tmp/test-spec-3-3.yaml")
assert_empty "$OUTPUT" "3.3  description only (no default) → ALLOW"

# 3.4 — https:// with variables → auto-fixed by adapt script
cleanup
cat > /tmp/test-spec-3-4.yaml <<'EOF'
openapi: "3.0.0"
info:
  title: Test
  version: "1.0"
servers:
  - url: "https://{domain}/api"
    variables:
      domain:
        description: "API domain"
paths: {}
EOF
OUTPUT=$(run_spec_hook "/tmp/test-spec-3-4.yaml")
assert_contains "$OUTPUT" "automatically fixed" "3.4  https:// with variables → auto-fixed"
assert_contains "$OUTPUT" "Stripped protocol" "3.4  reports protocol stripping"

# 3.5 — no protocol with variables → ALLOW
cleanup
cat > /tmp/test-spec-3-5.yaml <<'EOF'
openapi: "3.0.0"
info:
  title: Test
  version: "1.0"
servers:
  - url: "{domain}/api"
    variables:
      domain:
        description: "API domain"
paths: {}
EOF
OUTPUT=$(run_spec_hook "/tmp/test-spec-3-5.yaml")
assert_empty "$OUTPUT" "3.5  no protocol with variables → ALLOW"

# 3.6 — enum in parameter schema but NOT in servers → auto-fixed (default removed)
cleanup
cat > /tmp/test-spec-3-6.yaml <<'EOF'
openapi: "3.0.0"
info:
  title: Test
  version: "1.0"
servers:
  - url: "{domain}"
    variables:
      domain:
        default: "example.com"
        description: "API domain"
paths:
  /users:
    get:
      parameters:
        - name: status
          in: query
          schema:
            type: string
            enum:
              - active
              - inactive
EOF
OUTPUT=$(run_spec_hook "/tmp/test-spec-3-6.yaml")
assert_contains "$OUTPUT" "automatically fixed" "3.6  enum in params but not servers → auto-fixed"

# 3.7 — non-existent spec file → ALLOW (passthrough)
cleanup
OUTPUT=$(run_spec_hook "/tmp/nonexistent-spec.yaml")
assert_empty "$OUTPUT" "3.7  non-existent spec file → ALLOW (passthrough)"

# 3.8 — flat expose_to_workflow with variables → BLOCK via fallback (adapt doesn't fix x-cs-operation-config)
cleanup
cat > /tmp/test-spec-3-8.yaml <<'EOF'
openapi: "3.0.0"
info:
  title: Test
  version: "1.0"
servers:
  - url: "{domain}/api"
    variables:
      domain:
        description: "API domain"
paths:
  /users:
    get:
      operationId: listUsers
      x-cs-operation-config:
        expose_to_workflow: true
      responses:
        '200':
          description: OK
EOF
OUTPUT=$(run_spec_hook "/tmp/test-spec-3-8.yaml")
assert_json_field "$OUTPUT" '.hookSpecificOutput.decision' "block" "3.8  flat expose_to_workflow with vars → BLOCK (fallback)"

# 3.8b — flat expose_to_workflow WITHOUT variables (static URL) → BLOCK via fallback
cleanup
cat > /tmp/test-spec-3-8b.json <<'EOF'
{
  "openapi": "3.0.0",
  "info": {"title": "Test", "version": "1.0"},
  "servers": [{"url": "https://api.example.com"}],
  "paths": {
    "/users": {
      "get": {
        "operationId": "listUsers",
        "x-cs-operation-config": {
          "expose_to_workflow": true
        },
        "responses": {"200": {"description": "OK"}}
      }
    }
  }
}
EOF
OUTPUT=$(run_spec_hook "/tmp/test-spec-3-8b.json")
assert_json_field "$OUTPUT" '.hookSpecificOutput.decision' "block" "3.8b flat expose_to_workflow (static URL) → BLOCK (fallback)"
assert_contains "$OUTPUT" "Must be nested under a" "3.8b error message explains fix"

# 3.9 — nested workflow: key → ALLOW
cleanup
cat > /tmp/test-spec-3-9.yaml <<'EOF'
openapi: "3.0.0"
info:
  title: Test
  version: "1.0"
servers:
  - url: "{domain}/api"
    variables:
      domain:
        description: "API domain"
paths:
  /users:
    get:
      operationId: listUsers
      x-cs-operation-config:
        workflow:
          name: listUsers
          description: List all users
          expose_to_workflow: true
          system: false
      responses:
        '200':
          description: OK
EOF
OUTPUT=$(run_spec_hook "/tmp/test-spec-3-9.yaml")
assert_empty "$OUTPUT" "3.9  nested workflow: key → ALLOW"

# 3.10 — no expose_to_workflow at all → ALLOW
cleanup
cat > /tmp/test-spec-3-10.yaml <<'EOF'
openapi: "3.0.0"
info:
  title: Test
  version: "1.0"
servers:
  - url: "{domain}/api"
    variables:
      domain:
        description: "API domain"
paths:
  /users:
    get:
      operationId: listUsers
      responses:
        '200':
          description: OK
EOF
OUTPUT=$(run_spec_hook "/tmp/test-spec-3-10.yaml")
assert_empty "$OUTPUT" "3.10 no expose_to_workflow → ALLOW"

# 3.11 — JSON spec: default without enum → auto-fixed
cleanup
cat > /tmp/test-spec-3-11.json <<'EOF'
{
  "openapi": "3.0.0",
  "info": {"title": "Test", "version": "1.0"},
  "servers": [{"url": "{domain}", "variables": {"domain": {"default": "example.com", "description": "API domain"}}}],
  "paths": {}
}
EOF
OUTPUT=$(run_spec_hook "/tmp/test-spec-3-11.json")
assert_contains "$OUTPUT" "automatically fixed" "3.11 JSON: default without enum → auto-fixed"

# 3.12 — JSON spec: https:// with variables → auto-fixed
cleanup
cat > /tmp/test-spec-3-12.json <<'EOF'
{
  "openapi": "3.0.0",
  "info": {"title": "Test", "version": "1.0"},
  "servers": [{"url": "https://{domain}/api", "variables": {"domain": {"description": "API domain"}}}],
  "paths": {}
}
EOF
OUTPUT=$(run_spec_hook "/tmp/test-spec-3-12.json")
assert_contains "$OUTPUT" "automatically fixed" "3.12 JSON: https:// with variables → auto-fixed"

# 3.13 — JSON spec: flat expose_to_workflow (static URL) → BLOCK via fallback
cleanup
cat > /tmp/test-spec-3-13.json <<'EOF'
{
  "openapi": "3.0.0",
  "info": {"title": "Test", "version": "1.0"},
  "servers": [{"url": "https://api.example.com"}],
  "paths": {
    "/users": {
      "get": {
        "operationId": "listUsers",
        "x-cs-operation-config": {
          "expose_to_workflow": true
        },
        "responses": {"200": {"description": "OK"}}
      }
    }
  }
}
EOF
OUTPUT=$(run_spec_hook "/tmp/test-spec-3-13.json")
assert_json_field "$OUTPUT" '.hookSpecificOutput.decision' "block" "3.13 JSON: flat expose_to_workflow (static URL) → BLOCK"

# 3.14 — JSON spec: nested workflow key (static URL) → ALLOW
cleanup
cat > /tmp/test-spec-3-14.json <<'EOF'
{
  "openapi": "3.0.0",
  "info": {"title": "Test", "version": "1.0"},
  "servers": [{"url": "https://api.example.com"}],
  "paths": {
    "/users": {
      "get": {
        "operationId": "listUsers",
        "x-cs-operation-config": {
          "workflow": {
            "name": "listUsers",
            "description": "List all users",
            "expose_to_workflow": true,
            "system": false
          }
        },
        "responses": {"200": {"description": "OK"}}
      }
    }
  }
}
EOF
OUTPUT=$(run_spec_hook "/tmp/test-spec-3-14.json")
assert_empty "$OUTPUT" "3.14 JSON: nested workflow key (static URL) → ALLOW"

# 3.15 — oauth2 authorizationCode flow → auto-fixed
cleanup
cat > /tmp/test-spec-3-15.json <<'EOF'
{
  "openapi": "3.0.0",
  "info": {"title": "Test", "version": "1.0"},
  "servers": [{"url": "https://api.example.com"}],
  "components": {
    "securitySchemes": {
      "oauth2": {
        "type": "oauth2",
        "flows": {
          "authorizationCode": {
            "authorizationUrl": "/oauth/authorize",
            "tokenUrl": "/oauth/token",
            "scopes": {"read": "Read access"}
          }
        }
      }
    }
  },
  "security": [{"oauth2": []}],
  "paths": {}
}
EOF
OUTPUT=$(run_spec_hook "/tmp/test-spec-3-15.json")
assert_contains "$OUTPUT" "automatically fixed" "3.15 oauth2 authorizationCode → auto-fixed"
assert_contains "$OUTPUT" "Removed" "3.15 reports oauth2 removal"

# 3.16 — apiKey in Authorization header with SSWS description → bearerFormat added
cleanup
cat > /tmp/test-spec-3-16.json <<'EOF'
{
  "openapi": "3.0.0",
  "info": {"title": "Test", "version": "1.0"},
  "servers": [{"url": "https://api.example.com"}],
  "components": {
    "securitySchemes": {
      "apiToken": {
        "type": "apiKey",
        "in": "header",
        "name": "Authorization",
        "description": "SSWS {API Token}"
      }
    }
  },
  "security": [{"apiToken": []}],
  "paths": {}
}
EOF
OUTPUT=$(run_spec_hook "/tmp/test-spec-3-16.json")
assert_contains "$OUTPUT" "automatically fixed" "3.16 apiKey with SSWS description → bearerFormat added"
assert_contains "$OUTPUT" "Added bearerFormat" "3.16 reports bearerFormat inference"

# 3.17 — Okta-style combined issues (apiKey + oauth2 authCode + https + default) → all auto-fixed
cleanup
cat > /tmp/test-spec-3-17.yaml <<'EOF'
openapi: "3.0.0"
info:
  title: Okta Management API
  version: "5.0.0"
servers:
  - url: "https://{yourOktaDomain}"
    variables:
      yourOktaDomain:
        default: "subdomain.okta.com"
components:
  securitySchemes:
    apiToken:
      type: apiKey
      in: header
      name: Authorization
      description: "SSWS {API Token}"
    oauth2:
      type: oauth2
      flows:
        authorizationCode:
          authorizationUrl: /oauth2/v1/authorize
          tokenUrl: /oauth2/v1/token
          scopes:
            okta.users.read: Read users
security:
  - apiToken: []
  - oauth2: []
paths:
  /api/v1/users:
    get:
      operationId: listUsers
      summary: List users
      responses:
        '200':
          description: OK
EOF
OUTPUT=$(run_spec_hook "/tmp/test-spec-3-17.yaml")
assert_contains "$OUTPUT" "automatically fixed" "3.17 Okta-style combined issues → auto-fixed"
assert_contains "$OUTPUT" "Stripped protocol" "3.17 reports protocol stripping"
assert_contains "$OUTPUT" "Removed default" "3.17 reports default removal"
assert_contains "$OUTPUT" "Added bearerFormat" "3.17 reports bearerFormat inference"

# 3.18 — Clean spec (no issues) → ALLOW
cleanup
cat > /tmp/test-spec-3-18.json <<'EOF'
{
  "openapi": "3.0.0",
  "info": {"title": "Test", "version": "1.0"},
  "servers": [{"url": "https://api.example.com"}],
  "components": {
    "securitySchemes": {
      "bearer": {
        "type": "http",
        "scheme": "bearer"
      }
    }
  },
  "security": [{"bearer": []}],
  "paths": {
    "/status": {
      "get": {
        "operationId": "getStatus",
        "responses": {"200": {"description": "OK"}}
      }
    }
  }
}
EOF
OUTPUT=$(run_spec_hook "/tmp/test-spec-3-18.json")
assert_empty "$OUTPUT" "3.18 Clean spec (no issues) → ALLOW"

# 3.19 — Duplicate parameters (path-level + operation-level) → auto-fixed
cleanup
cat > /tmp/test-spec-3-19.yaml <<'EOF'
openapi: "3.0.0"
info:
  title: Test
  version: "1.0"
servers:
  - url: "https://api.example.com"
components:
  parameters:
    pathUserId:
      name: userId
      in: path
      required: true
      schema:
        type: string
paths:
  /users/{userId}/subscriptions:
    parameters:
      - $ref: '#/components/parameters/pathUserId'
    get:
      operationId: listSubscriptionsUser
      parameters:
        - name: userId
          in: path
          required: true
          schema:
            type: string
      responses:
        '200':
          description: OK
EOF
OUTPUT=$(run_spec_hook "/tmp/test-spec-3-19.yaml")
assert_contains "$OUTPUT" "automatically fixed" "3.19 duplicate params (path + op level) → auto-fixed"
assert_contains "$OUTPUT" "Removed duplicate param" "3.19 reports param dedup"

# 3.20 — Duplicate $ref parameters (same ref at both levels) → auto-fixed
cleanup
cat > /tmp/test-spec-3-20.yaml <<'EOF'
openapi: "3.0.0"
info:
  title: Test
  version: "1.0"
servers:
  - url: "https://api.example.com"
components:
  parameters:
    pathGroupId:
      name: groupId
      in: path
      required: true
      schema:
        type: string
paths:
  /groups/{groupId}/owners:
    parameters:
      - $ref: '#/components/parameters/pathGroupId'
    post:
      operationId: assignGroupOwner
      parameters:
        - $ref: '#/components/parameters/pathGroupId'
      responses:
        '200':
          description: OK
EOF
OUTPUT=$(run_spec_hook "/tmp/test-spec-3-20.yaml")
assert_contains "$OUTPUT" "automatically fixed" "3.20 duplicate \$ref params → auto-fixed"
assert_contains "$OUTPUT" "Removed duplicate param" "3.20 reports \$ref dedup"

# ---------- Section 3b: PreToolUse — Hand-Written OpenAPI Spec Detection ----------

printf "\n${BOLD}Section 3b: PreToolUse — Hand-Written OpenAPI Spec Detection${RESET}\n\n"

# 3b.1 — Write tool with openapi: in YAML file → advisory nudge
cleanup
JSON=$(jq -n '{
  hook_event_name: "PreToolUse",
  tool_name: "Write",
  tool_input: {
    file_path: "/tmp/my-api.yaml",
    content: "openapi: 3.0.3\ninfo:\n  title: My API\npaths:\n  /users:\n    get:\n      summary: List users"
  }
}')
OUTPUT=$(run_hook "$HOOK" "$JSON")
assert_contains "$OUTPUT" "writing an OpenAPI spec from scratch" "3b.1 Write YAML with openapi: → advisory"
assert_contains "$OUTPUT" "Download the real spec" "3b.1 advises downloading vendor spec"

# 3b.2 — Write tool with "openapi" in JSON file → advisory nudge
cleanup
JSON=$(jq -n '{
  hook_event_name: "PreToolUse",
  tool_name: "Write",
  tool_input: {
    file_path: "/tmp/my-api.json",
    content: "{\"openapi\": \"3.0.3\", \"info\": {\"title\": \"My API\"}}"
  }
}')
OUTPUT=$(run_hook "$HOOK" "$JSON")
assert_contains "$OUTPUT" "writing an OpenAPI spec from scratch" "3b.2 Write JSON with openapi → advisory"

# 3b.3 — Write tool with non-spec YAML → no output
cleanup
JSON=$(jq -n '{
  hook_event_name: "PreToolUse",
  tool_name: "Write",
  tool_input: {
    file_path: "/tmp/workflow.yaml",
    content: "name: my-workflow\ndescription: On-demand workflow\ntrigger:\n  name: On demand"
  }
}')
OUTPUT=$(run_hook "$HOOK" "$JSON")
assert_empty "$OUTPUT" "3b.3 Write non-OpenAPI YAML → no output"

# 3b.4 — Write tool with non-YAML file → no output
cleanup
JSON=$(jq -n '{
  hook_event_name: "PreToolUse",
  tool_name: "Write",
  tool_input: {
    file_path: "/tmp/readme.md",
    content: "# My App\nopenapi specs are great"
  }
}')
OUTPUT=$(run_hook "$HOOK" "$JSON")
assert_empty "$OUTPUT" "3b.4 Write non-YAML/JSON file → no output"

# ---------- Section 3c: PreToolUse — Manifest Entrypoint Protection ----------

printf "\n${BOLD}Section 3c: PreToolUse — Manifest Entrypoint Protection${RESET}\n\n"

# 3c.1 — Edit entrypoint in manifest.yml → advisory
cleanup
JSON=$(jq -n '{
  hook_event_name: "PreToolUse",
  tool_name: "Edit",
  tool_input: {
    file_path: "/tmp/okta-users/manifest.yml",
    old_string: "entrypoint: ui/extensions/okta-users-ext/src/dist/index.html",
    new_string: "entrypoint: src/dist/index.html"
  }
}')
OUTPUT=$(run_hook "$HOOK" "$JSON")
assert_contains "$OUTPUT" "Do NOT edit path or entrypoint" "3c.1 Edit entrypoint in manifest.yml → advisory"

# 3c.2 — Edit path for ui/extensions in manifest.yml → advisory
cleanup
JSON=$(jq -n '{
  hook_event_name: "PreToolUse",
  tool_name: "Edit",
  tool_input: {
    file_path: "/tmp/okta-users/manifest.yml",
    old_string: "path: ui/extensions/okta-users-ext/src/dist",
    new_string: "path: ui/extensions/okta-users-ext/dist"
  }
}')
OUTPUT=$(run_hook "$HOOK" "$JSON")
assert_contains "$OUTPUT" "Do NOT edit path or entrypoint" "3c.2 Edit extension path in manifest.yml → advisory"

# 3c.3 — Edit unrelated field in manifest.yml → no output
cleanup
JSON=$(jq -n '{
  hook_event_name: "PreToolUse",
  tool_name: "Edit",
  tool_input: {
    file_path: "/tmp/okta-users/manifest.yml",
    old_string: "description: Old description",
    new_string: "description: New description"
  }
}')
OUTPUT=$(run_hook "$HOOK" "$JSON")
assert_empty "$OUTPUT" "3c.3 Edit description in manifest.yml → no output"

# 3c.4 — Edit entrypoint in non-manifest file → no output
cleanup
JSON=$(jq -n '{
  hook_event_name: "PreToolUse",
  tool_name: "Edit",
  tool_input: {
    file_path: "/tmp/okta-users/vite.config.js",
    old_string: "entrypoint: old",
    new_string: "entrypoint: new"
  }
}')
OUTPUT=$(run_hook "$HOOK" "$JSON")
assert_empty "$OUTPUT" "3c.4 Edit entrypoint in non-manifest file → no output"

# ---------- Section 4: PreToolUse — Marker File Advisory ----------

printf "\n${BOLD}Section 4: PreToolUse — Marker File Advisory${RESET}\n\n"

# 4.1 — Marker exists, tool is Skill → no output, marker deleted
cleanup
echo "$$" > "$MARKER"
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Skill", tool_input: {skill: "crowdstrike-falcon-foundry:development-workflow"}}')
OUTPUT=$(run_hook "$HOOK" "$JSON")
assert_empty "$OUTPUT" "4.1  Skill tool → no output"
assert_marker_not_exists "4.1  Skill tool → marker deleted"

# 4.2 — Marker exists, tool is Bash (non-foundry) → advisory context
cleanup
echo "$$" > "$MARKER"
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "ls -la"}}')
OUTPUT=$(run_hook "$HOOK" "$JSON")
assert_contains "$OUTPUT" "Foundry plugin reminder" "4.2  Bash (non-foundry) → advisory"

# 4.3 — Marker exists, tool is Read → advisory context
cleanup
echo "$$" > "$MARKER"
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Read", tool_input: {file_path: "/tmp/foo"}}')
OUTPUT=$(run_hook "$HOOK" "$JSON")
assert_contains "$OUTPUT" "Foundry plugin reminder" "4.3  Read tool → advisory"

# 4.4 — No marker, tool is Bash → no output
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "ls -la"}}')
OUTPUT=$(run_hook "$HOOK" "$JSON")
assert_empty "$OUTPUT" "4.4  No marker, Bash → no output"

# ---------- Section 5: Superpowers Bridge ----------

printf "\n${BOLD}Section 5: Superpowers Bridge${RESET}\n\n"

# 5.1 — superpowers:brainstorming → redirect
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Skill", tool_input: {skill: "superpowers:brainstorming"}}')
OUTPUT=$(run_hook "$BRIDGE" "$JSON")
assert_contains "$OUTPUT" "STOP. Do NOT proceed" "5.1  superpowers:brainstorming → redirect"

# 5.2 — brainstorming (short form) → redirect
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Skill", tool_input: {skill: "brainstorming"}}')
OUTPUT=$(run_hook "$BRIDGE" "$JSON")
assert_contains "$OUTPUT" "STOP. Do NOT proceed" "5.2  brainstorming (short form) → redirect"

# 5.3 — superpowers:writing-plans → advisory
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Skill", tool_input: {skill: "superpowers:writing-plans"}}')
OUTPUT=$(run_hook "$BRIDGE" "$JSON")
assert_contains "$OUTPUT" "FOUNDRY PLUGIN INSTALLED" "5.3  writing-plans → advisory"

# 5.4 — superpowers:executing-plans → advisory
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Skill", tool_input: {skill: "superpowers:executing-plans"}}')
OUTPUT=$(run_hook "$BRIDGE" "$JSON")
assert_contains "$OUTPUT" "FOUNDRY PLUGIN INSTALLED" "5.4  executing-plans → advisory"

# 5.5 — superpowers:test-driven-development → no output
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Skill", tool_input: {skill: "superpowers:test-driven-development"}}')
OUTPUT=$(run_hook "$BRIDGE" "$JSON")
assert_empty "$OUTPUT" "5.5  test-driven-development → no output"

# 5.6 — crowdstrike-falcon-foundry:development-workflow → no output
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Skill", tool_input: {skill: "crowdstrike-falcon-foundry:development-workflow"}}')
OUTPUT=$(run_hook "$BRIDGE" "$JSON")
assert_empty "$OUTPUT" "5.6  foundry skill → no output"

# ---------- Section 6: CLI Guard — --no-prompt Enforcement ----------

printf "\n${BOLD}Section 6: CLI Guard — --no-prompt Enforcement${RESET}\n\n"

# 6.1 — foundry apps create without --no-prompt → advisory
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry apps create --name test"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_contains "$OUTPUT" "missing --no-prompt" "6.1  apps create without --no-prompt → advisory"
assert_not_contains "$OUTPUT" "deny" "6.1  no deny (advisory only)"

# 6.2 — foundry apps create with --no-prompt → no output (name confirm disabled for isolation)
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry apps create --name test --no-prompt"}}')
OUTPUT=$(FOUNDRY_SKIP_NAME_CONFIRM=1 run_hook "$GUARD" "$JSON")
assert_empty "$OUTPUT" "6.2  apps create with --no-prompt → pass"

# 6.3 — foundry apps deploy (no --no-prompt needed) → no output
# deploy works non-interactively when --change-type/--change-log are provided
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry apps deploy --change-type Patch --change-log \"bugfix\""}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_empty "$OUTPUT" "6.3  apps deploy → pass (no --no-prompt needed)"

# 6.4 — foundry ui pages create without --no-prompt → advisory
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry ui pages create --name MyPage --from-template React"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_contains "$OUTPUT" "missing --no-prompt" "6.4  ui pages create without --no-prompt → advisory"

# 6.5 — foundry functions create with --no-prompt → no output (name confirm disabled for isolation)
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry functions create --name myfunc --language python --no-prompt"}}')
OUTPUT=$(FOUNDRY_SKIP_NAME_CONFIRM=1 run_hook "$GUARD" "$JSON")
assert_empty "$OUTPUT" "6.5  functions create with --no-prompt → pass"

# 6.6 — mkdir api-integrations → advisory
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "mkdir -p api-integrations"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_contains "$OUTPUT" "Manual creation" "6.6  mkdir api-integrations → advisory"
assert_not_contains "$OUTPUT" "deny" "6.6  no deny (advisory only)"

# 6.7 — touch manifest.yml → advisory
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "touch manifest.yml"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_contains "$OUTPUT" "Manual creation" "6.7  touch manifest.yml → advisory"

# 6.8 — echo > manifest.yml → advisory
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "echo \"name: test\" > manifest.yml"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_contains "$OUTPUT" "Manual creation" "6.8  echo > manifest.yml → advisory"

# 6.9 — normal bash command → no output
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "ls -la"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_empty "$OUTPUT" "6.9  normal command → pass"

# 6.10 — non-Bash tool → no output
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Read", tool_input: {file_path: "/tmp/foo"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_empty "$OUTPUT" "6.10 non-Bash tool → pass"

# 6.11 — foundry login (no --no-prompt needed) → no output
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry login"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_empty "$OUTPUT" "6.11 foundry login → pass (no --no-prompt needed)"

# 6.12 — foundry apps release with --no-prompt → no output
# release requires --no-prompt for non-interactive operation
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry apps release --deployment-id abc123 --change-type Patch --notes \"initial release\" --no-prompt"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_empty "$OUTPUT" "6.12 apps release with --no-prompt → pass"

# 6.13 — foundry rtr-scripts create without --no-prompt → advisory
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry rtr-scripts create --name myscript"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_contains "$OUTPUT" "missing --no-prompt" "6.13 rtr-scripts create without --no-prompt → advisory"

# 6.14 — foundry profile create without --no-prompt → advisory
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry profile create --name us-2"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_contains "$OUTPUT" "missing --no-prompt" "6.14 profile create without --no-prompt → advisory"

# 6.15 — foundry workflows create without --no-prompt → advisory
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry workflows create --name my-wf --spec /tmp/wf.yaml"}}')
OUTPUT=$(FOUNDRY_SKIP_NAME_CONFIRM=1 run_hook "$GUARD" "$JSON")
assert_contains "$OUTPUT" "missing --no-prompt" "6.15 workflows create without --no-prompt → advisory"

# 6.16 — foundry api-integrations create without --no-prompt → advisory
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry api-integrations create --name X --spec /tmp/spec.yaml"}}')
OUTPUT=$(FOUNDRY_SKIP_NAME_CONFIRM=1 run_hook "$GUARD" "$JSON")
assert_contains "$OUTPUT" "missing --no-prompt" "6.16 api-integrations create without --no-prompt → advisory"

# 6.17 — foundry ui extensions create without --sockets → advisory
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry ui extensions create --name my-ext --from-template React --no-prompt"}}')
OUTPUT=$(FOUNDRY_SKIP_NAME_CONFIRM=1 run_hook "$GUARD" "$JSON")
assert_contains "$OUTPUT" "missing --sockets" "6.17 ui extensions create without --sockets → advisory"

# 6.18 — foundry ui extensions create with --sockets → pass (name confirm disabled for isolation)
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry ui extensions create --name my-ext --from-template React --sockets \"activity.detections.details\" --no-prompt"}}')
OUTPUT=$(FOUNDRY_SKIP_NAME_CONFIRM=1 run_hook "$GUARD" "$JSON")
assert_empty "$OUTPUT" "6.18 ui extensions create with --sockets → pass"

# 6.18a — foundry ui extensions create with invalid socket ID → advisory
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry ui extensions create --name my-ext --from-template React --sockets \"activity.hosts.details\" --no-prompt"}}')
OUTPUT=$(FOUNDRY_SKIP_NAME_CONFIRM=1 run_hook "$GUARD" "$JSON")
assert_contains "$OUTPUT" "Invalid socket ID" "6.18a invalid socket ID → advisory"

# 6.18b — foundry ui extensions create with hosts.host.panel → pass
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry ui extensions create --name my-ext --from-template React --sockets \"hosts.host.panel\" --no-prompt"}}')
OUTPUT=$(FOUNDRY_SKIP_NAME_CONFIRM=1 run_hook "$GUARD" "$JSON")
assert_empty "$OUTPUT" "6.18b valid socket hosts.host.panel → pass"

# 6.18c — foundry ui extensions create with xdr.cases.panel → pass
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry ui extensions create --name my-ext --from-template React --sockets \"xdr.cases.panel\" --no-prompt"}}')
OUTPUT=$(FOUNDRY_SKIP_NAME_CONFIRM=1 run_hook "$GUARD" "$JSON")
assert_empty "$OUTPUT" "6.18c valid socket xdr.cases.panel → pass"

# 6.19 — foundry apps validate without --no-prompt → advisory
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry apps validate"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_contains "$OUTPUT" "missing --no-prompt" "6.19 apps validate without --no-prompt → advisory"

# 6.20 — foundry apps validate with --no-prompt → no output
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry apps validate --no-prompt"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_empty "$OUTPUT" "6.20 apps validate with --no-prompt → pass"

# =============================================
# Section 7: Skill Description Validation
# =============================================
printf "\n${BOLD}--- Section 7: Skill Description Validation ---${RESET}\n\n"

SKILL_DIR="./skills"

# 7.1 — All descriptions include triggering guidance
# Accepts either: "This skill should be used when" (v1) or "TRIGGER when" (v2 Anthropic pattern)
for skill_dir in "$SKILL_DIR"/*/; do
  SKILL_FILE="$skill_dir/SKILL.md"
  if [ ! -f "$SKILL_FILE" ]; then continue; fi
  SKILL_NAME=$(basename "$skill_dir")
  DESC=$(grep '^description:' "$SKILL_FILE" | head -1 | sed 's/^description: *//')
  TOTAL=$((TOTAL + 1))
  if echo "$DESC" | grep -qE "^This skill should be used when|TRIGGER when"; then
    PASS=$((PASS + 1))
    printf "${GREEN}  PASS${RESET} 7.1 %s has triggering guidance\n" "$SKILL_NAME"
  else
    FAIL=$((FAIL + 1))
    printf "${RED}  FAIL${RESET} 7.1 %s description should include 'This skill should be used when' or 'TRIGGER when'\n" "$SKILL_NAME"
    printf "       got: %.100s\n" "$DESC"
  fi
done

# 7.2 — All descriptions include quoted trigger phrases
for skill_dir in "$SKILL_DIR"/*/; do
  SKILL_FILE="$skill_dir/SKILL.md"
  if [ ! -f "$SKILL_FILE" ]; then continue; fi
  SKILL_NAME=$(basename "$skill_dir")
  DESC=$(grep '^description:' "$SKILL_FILE" | head -1 | sed 's/^description: *//')
  TOTAL=$((TOTAL + 1))
  if echo "$DESC" | grep -qE '"[^"]+"|`[^`]+`'; then
    PASS=$((PASS + 1))
    printf "${GREEN}  PASS${RESET} 7.2 %s has quoted trigger phrases\n" "$SKILL_NAME"
  else
    FAIL=$((FAIL + 1))
    printf "${RED}  FAIL${RESET} 7.2 %s description should include quoted trigger phrases\n" "$SKILL_NAME"
  fi
done

# 7.3 — No description exceeds 1024 characters
for skill_dir in "$SKILL_DIR"/*/; do
  SKILL_FILE="$skill_dir/SKILL.md"
  if [ ! -f "$SKILL_FILE" ]; then continue; fi
  SKILL_NAME=$(basename "$skill_dir")
  DESC=$(grep '^description:' "$SKILL_FILE" | head -1 | sed 's/^description: *//')
  DESC_LEN=${#DESC}
  TOTAL=$((TOTAL + 1))
  if [ "$DESC_LEN" -le 1024 ]; then
    PASS=$((PASS + 1))
    printf "${GREEN}  PASS${RESET} 7.3 %s description length (%d chars)\n" "$SKILL_NAME" "$DESC_LEN"
  else
    FAIL=$((FAIL + 1))
    printf "${RED}  FAIL${RESET} 7.3 %s description exceeds 1024 chars (%d chars)\n" "$SKILL_NAME" "$DESC_LEN"
  fi
done

# =============================================
# Section 8: CLI Guard — Name Confirmation
# =============================================
printf "\n${BOLD}--- Section 8: CLI Guard — Name Confirmation ---${RESET}\n\n"

# 8.1 — foundry apps create with --name → name confirmation advisory
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry apps create --name \"my-app\" --no-prompt --no-git"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_contains "$OUTPUT" "Confirm the resource name" "8.1  apps create → name confirmation advisory"
assert_contains "$OUTPUT" "my-app" "8.1  advisory includes the resource name"

# 8.2 — foundry functions create with --name → name confirmation advisory
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry functions create --name my-func --language python --no-prompt"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_contains "$OUTPUT" "Confirm the resource name" "8.2  functions create → name confirmation advisory"
assert_contains "$OUTPUT" "my-func" "8.2  advisory includes function name"

# 8.3 — foundry collections create with --name → name confirmation advisory
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry collections create --name my_col --schema /tmp/s.json --no-prompt"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_contains "$OUTPUT" "Confirm the resource name" "8.3  collections create → name confirmation advisory"
assert_contains "$OUTPUT" "my_col" "8.3  advisory includes collection name"

# 8.4 — FOUNDRY_SKIP_NAME_CONFIRM=1 → bypasses confirmation
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry apps create --name \"my-app\" --no-prompt --no-git"}}')
OUTPUT=$(FOUNDRY_SKIP_NAME_CONFIRM=1 run_hook "$GUARD" "$JSON")
assert_empty "$OUTPUT" "8.4  FOUNDRY_SKIP_NAME_CONFIRM=1 → no advisory"

# 8.5 — foundry apps deploy (no --name) → no confirmation
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry apps deploy --change-type Patch --change-log \"fix\""}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_empty "$OUTPUT" "8.5  apps deploy → no name confirmation"

# 8.6 — foundry workflows create with --name → name confirmation advisory
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry workflows create --name \"My Workflow\" --spec /tmp/wf.yaml --no-prompt"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_contains "$OUTPUT" "Confirm the resource name" "8.6  workflows create → name confirmation advisory"
assert_contains "$OUTPUT" "My Workflow" "8.6  advisory includes workflow name"

# 8.7 — foundry api-integrations create with --name → name confirmation advisory
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry api-integrations create --name MyApi --spec /tmp/spec.yaml --no-prompt"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_contains "$OUTPUT" "Confirm the resource name" "8.7  api-integrations create → name confirmation advisory"
assert_contains "$OUTPUT" "MyApi" "8.7  advisory includes API integration name"

# 8.8 — create without --name → no confirmation (no name to confirm)
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry apps create --no-prompt"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_empty "$OUTPUT" "8.8  create without --name → no confirmation"

# 8.9 — --name=value syntax (equals sign) → name confirmation advisory
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry apps create --name=my-app --no-prompt"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_contains "$OUTPUT" "Confirm the resource name" "8.9  --name=value syntax → name confirmation advisory"
assert_contains "$OUTPUT" "my-app" "8.9  advisory includes name from equals syntax"

# 8.10 — --name followed by a flag (no actual value) → no confirmation
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry apps create --name --no-prompt --no-git"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_empty "$OUTPUT" "8.10 --name followed by flag → no false positive"

# 8.11 — single-quoted name with spaces → name confirmation advisory
cleanup
JSON=$(jq -n --arg cmd "foundry workflows create --name 'My Workflow' --spec /tmp/wf.yaml --no-prompt" \
  '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $cmd}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_contains "$OUTPUT" "Confirm the resource name" "8.11 single-quoted name → name confirmation advisory"
assert_contains "$OUTPUT" "My Workflow" "8.11 advisory includes single-quoted name"

# 8.12 — foundry profile create → NO name confirmation (local config, not a resource)
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry profile create --name us-2 --no-prompt"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_empty "$OUTPUT" "8.12 profile create → no name confirmation (local config)"

# 8.13 — foundry ui pages create with --name → name confirmation advisory
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry ui pages create --name my-page --from-template React --no-prompt"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_contains "$OUTPUT" "Confirm the resource name" "8.13 ui pages create → name confirmation advisory"
assert_contains "$OUTPUT" "my-page" "8.13 advisory includes page name"

# 8.14 — foundry ui extensions create with --name → name confirmation advisory
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry ui extensions create --name my-ext --from-template React --sockets \"activity.detections.details\" --no-prompt"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_contains "$OUTPUT" "Confirm the resource name" "8.14 ui extensions create → name confirmation advisory"
assert_contains "$OUTPUT" "my-ext" "8.14 advisory includes extension name"

# 8.15 — --name="value" (equals with double quotes) → name confirmation advisory
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry apps create --name=\"my-app\" --no-prompt"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_contains "$OUTPUT" "Confirm the resource name" "8.15 --name=\"value\" syntax → name confirmation advisory"
assert_contains "$OUTPUT" "my-app" "8.15 advisory includes name from equals+quotes"

# 8.16 — foundry rtr-scripts create with --name → name confirmation advisory
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry rtr-scripts create --name my-script --no-prompt"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_contains "$OUTPUT" "Confirm the resource name" "8.16 rtr-scripts create → name confirmation advisory"
assert_contains "$OUTPUT" "my-script" "8.16 advisory includes rtr-script name"

# 8.17 — --name="" (equals with empty double quotes) → no confirmation
cleanup
JSON=$(jq -n '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "foundry apps create --name=\"\" --no-prompt"}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_empty "$OUTPUT" "8.17 --name=\"\" (empty) → no confirmation"

# 8.18 — --name='' (equals with empty single quotes) → no confirmation
cleanup
JSON=$(jq -n --arg cmd "foundry apps create --name='' --no-prompt" \
  '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $cmd}}')
OUTPUT=$(run_hook "$GUARD" "$JSON")
assert_empty "$OUTPUT" "8.18 --name='' (empty) → no confirmation"

# =============================================
# Section 9: SessionStart Hook — foundry-session-start.sh
# =============================================
printf "\n${BOLD}--- Section 9: SessionStart Hook — foundry-session-start.sh ---${RESET}\n\n"

ENV_HOOK="./hooks/foundry-session-start.sh"

# 9.1 — Warns when CLI version is below minimum
cleanup
FAKE_BIN=$(mktemp -d)
cat > "$FAKE_BIN/foundry" << 'FEOF'
#!/usr/bin/env bash
echo "foundry 1.9.3 (git: abc123) build_date: 2026-01-01T00:00:00Z"
FEOF
chmod +x "$FAKE_BIN/foundry"
OUTPUT=$(PATH="$FAKE_BIN:$PATH" bash "$ENV_HOOK" 2>&1)
assert_contains "$OUTPUT" "IMPORTANT" "9.1  warns when CLI version is below minimum (1.9.3 < 2.0.1)"
rm -rf "$FAKE_BIN"

# 9.2 — No warning when CLI version meets minimum
cleanup
FAKE_BIN=$(mktemp -d)
cat > "$FAKE_BIN/foundry" << 'FEOF'
#!/usr/bin/env bash
echo "foundry 2.0.1 (git: abc123) build_date: 2026-04-14T00:00:00Z"
FEOF
chmod +x "$FAKE_BIN/foundry"
OUTPUT=$(PATH="$FAKE_BIN:$PATH" bash "$ENV_HOOK" 2>&1)
assert_empty "$OUTPUT" "9.2  no warning when CLI version meets minimum (2.0.1 = 2.0.1)"
rm -rf "$FAKE_BIN"

# 9.3 — No warning when CLI version exceeds minimum
cleanup
FAKE_BIN=$(mktemp -d)
cat > "$FAKE_BIN/foundry" << 'FEOF'
#!/usr/bin/env bash
echo "foundry 2.1.0 (git: abc123) build_date: 2026-06-01T00:00:00Z"
FEOF
chmod +x "$FAKE_BIN/foundry"
OUTPUT=$(PATH="$FAKE_BIN:$PATH" bash "$ENV_HOOK" 2>&1)
assert_empty "$OUTPUT" "9.3  no warning when CLI version exceeds minimum (2.1.0 > 2.0.1)"
rm -rf "$FAKE_BIN"

# 9.4 — Warning includes upgrade instructions
cleanup
FAKE_BIN=$(mktemp -d)
cat > "$FAKE_BIN/foundry" << 'FEOF'
#!/usr/bin/env bash
echo "foundry 1.5.0 (git: abc123) build_date: 2025-06-01T00:00:00Z"
FEOF
chmod +x "$FAKE_BIN/foundry"
OUTPUT=$(PATH="$FAKE_BIN:$PATH" bash "$ENV_HOOK" 2>&1)
assert_contains "$OUTPUT" "brew upgrade" "9.4  warning includes brew upgrade instructions"
rm -rf "$FAKE_BIN"

# 9.5 — Warning includes Windows download URL
cleanup
FAKE_BIN=$(mktemp -d)
cat > "$FAKE_BIN/foundry" << 'FEOF'
#!/usr/bin/env bash
echo "foundry 1.5.0 (git: abc123) build_date: 2025-06-01T00:00:00Z"
FEOF
chmod +x "$FAKE_BIN/foundry"
OUTPUT=$(PATH="$FAKE_BIN:$PATH" bash "$ENV_HOOK" 2>&1)
assert_contains "$OUTPUT" "Windows" "9.5  warning includes Windows download instructions"
rm -rf "$FAKE_BIN"

# 9.6 — Warning instructs Claude to prompt user
cleanup
FAKE_BIN=$(mktemp -d)
cat > "$FAKE_BIN/foundry" << 'FEOF'
#!/usr/bin/env bash
echo "foundry 1.5.0 (git: abc123) build_date: 2025-06-01T00:00:00Z"
FEOF
chmod +x "$FAKE_BIN/foundry"
OUTPUT=$(PATH="$FAKE_BIN:$PATH" bash "$ENV_HOOK" 2>&1)
assert_contains "$OUTPUT" "AskUserQuestion" "9.6  warning instructs Claude to prompt user"
rm -rf "$FAKE_BIN"

# 9.7 — No error when Foundry CLI is not installed
cleanup
FAKE_BIN=$(mktemp -d)
cat > "$FAKE_BIN/foundry" << 'FEOF'
#!/usr/bin/env bash
exit 1
FEOF
chmod +x "$FAKE_BIN/foundry"
OUTPUT=$(PATH="$FAKE_BIN:$PATH" bash "$ENV_HOOK" 2>&1)
EXIT_CODE=$?
TOTAL=$((TOTAL + 1))
if [ "$EXIT_CODE" -eq 0 ]; then
  PASS=$((PASS + 1))
  printf "${GREEN}  PASS${RESET} 9.7  exits cleanly when Foundry CLI is not installed\n"
else
  FAIL=$((FAIL + 1))
  printf "${RED}  FAIL${RESET} 9.7  should exit 0 even when Foundry CLI is not installed\n"
fi
rm -rf "$FAKE_BIN"

# 9.8 — Warns for 2.0.0 (below 2.0.1 minimum)
cleanup
FAKE_BIN=$(mktemp -d)
cat > "$FAKE_BIN/foundry" << 'FEOF'
#!/usr/bin/env bash
echo "foundry 2.0.0 (git: abc123) build_date: 2026-04-14T00:00:00Z"
FEOF
chmod +x "$FAKE_BIN/foundry"
OUTPUT=$(PATH="$FAKE_BIN:$PATH" bash "$ENV_HOOK" 2>&1)
assert_contains "$OUTPUT" "IMPORTANT" "9.8  warns for 2.0.0 (below 2.0.1 minimum)"
rm -rf "$FAKE_BIN"

# 9.9 — Sets FOUNDRY_UI_HEADLESS_MODE for older CLIs
cleanup
FAKE_BIN=$(mktemp -d)
ENV_TMP=$(mktemp)
cat > "$FAKE_BIN/foundry" << 'FEOF'
#!/usr/bin/env bash
echo "foundry 1.9.3 (git: abc123) build_date: 2026-01-01T00:00:00Z"
FEOF
chmod +x "$FAKE_BIN/foundry"
PATH="$FAKE_BIN:$PATH" CLAUDE_ENV_FILE="$ENV_TMP" bash "$ENV_HOOK" 2>/dev/null
OUTPUT=$(cat "$ENV_TMP")
assert_contains "$OUTPUT" "FOUNDRY_UI_HEADLESS_MODE=true" "9.9  sets FOUNDRY_UI_HEADLESS_MODE for older CLIs"
rm -rf "$FAKE_BIN" "$ENV_TMP"

# 9.10 — Does NOT set FOUNDRY_UI_HEADLESS_MODE for 2.0.1+
cleanup
FAKE_BIN=$(mktemp -d)
ENV_TMP=$(mktemp)
cat > "$FAKE_BIN/foundry" << 'FEOF'
#!/usr/bin/env bash
echo "foundry 2.0.1 (git: abc123) build_date: 2026-04-14T00:00:00Z"
FEOF
chmod +x "$FAKE_BIN/foundry"
PATH="$FAKE_BIN:$PATH" CLAUDE_ENV_FILE="$ENV_TMP" bash "$ENV_HOOK" 2>/dev/null
OUTPUT=$(cat "$ENV_TMP")
assert_empty "$OUTPUT" "9.10 does NOT set FOUNDRY_UI_HEADLESS_MODE for 2.0.1+"
rm -rf "$FAKE_BIN" "$ENV_TMP"

# ---------- Cleanup and Summary ----------

cleanup
printf "\n${BOLD}=========================================${RESET}\n"
printf "${BOLD}  RESULTS${RESET}\n"
printf "${BOLD}=========================================${RESET}\n\n"
printf "  ${GREEN}Passed: %d${RESET}\n" "$PASS"
printf "  ${RED}Failed: %d${RESET}\n" "$FAIL"
printf "  Total:  %d\n\n" "$TOTAL"

if [ "$FAIL" -eq 0 ]; then
  printf "${GREEN}${BOLD}  All tests passed.${RESET}\n\n"
  exit 0
else
  printf "${RED}${BOLD}  %d test(s) failed.${RESET}\n\n" "$FAIL"
  exit 1
fi
