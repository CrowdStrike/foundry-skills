#!/usr/bin/env python3
# pylint: disable=invalid-name
"""
adapt-spec-for-foundry.py — Transform OpenAPI specs for Falcon Foundry

Applies deterministic transformations derived from 12 production Foundry sample apps:
  1. Swagger 2.0 conversion: Convert to OpenAPI 3.0 via swagger2openapi (npx)
  2. Server URLs: Strip https:// from variable-based URLs, remove default from variables
  3. Auth: Infer API key prefix via bearerFormat, remove oauth2 authorizationCode
  4. Parameters: Remove operation-level params that duplicate path-level params

Does NOT add x-cs-operation-config — which operations to expose to workflows is a
prompt-driven decision the agent makes based on user requirements.

Usage:
  python3 scripts/adapt-spec-for-foundry.py /tmp/VendorApi.yaml
  python3 scripts/adapt-spec-for-foundry.py /tmp/VendorApi.json -o /tmp/adapted.json
  python3 scripts/adapt-spec-for-foundry.py spec.yaml --dry-run
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

try:
    import yaml
    HAS_YAML = True
except ImportError:
    HAS_YAML = False


def convert_swagger_to_openapi(path):
    """Convert Swagger 2.0 to OpenAPI 3.0 using swagger2openapi (npx).

    Returns (converted_path, True) if conversion happened, (original_path, False) otherwise.
    CrowdStrike's own Falcon API spec requires this conversion for Foundry compatibility.
    """
    text = Path(path).read_text(encoding='utf-8', errors='replace')

    # Detect Swagger 2.0
    is_swagger = False
    if '"swagger"' in text[:500] or "'swagger'" in text[:500]:
        is_swagger = True
    elif text.lstrip().startswith('swagger:'):
        is_swagger = True

    if not is_swagger:
        return path, False

    # Determine output format based on input
    if path.endswith(('.yaml', '.yml')):
        out_path = path.rsplit('.', 1)[0] + '.openapi3.yaml'
        cmd = [
            'npx', '-y', '-p', 'swagger2openapi', 'swagger2openapi',
            '--', path, '-o', out_path, '--yaml',
        ]
    else:
        out_path = path.rsplit('.', 1)[0] + '.openapi3.json'
        cmd = [
            'npx', '-y', '-p', 'swagger2openapi', 'swagger2openapi',
            '--', path, '-o', out_path,
        ]

    print("Converting Swagger 2.0 → OpenAPI 3.0...")
    print(f"  Command: {' '.join(cmd)}")

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120, check=False)
        if result.returncode == 0 and Path(out_path).exists():
            print(f"  Converted: {out_path}")
            print()
            return out_path, True

        print(f"  WARNING: swagger2openapi failed (exit {result.returncode})")
        if result.stderr:
            # Show first meaningful error line
            for line in result.stderr.splitlines()[:3]:
                print(f"    {line}")
        print("  Continuing with original file.")
        print()
        return path, False
    except FileNotFoundError:
        print("  WARNING: npx not found. Install Node.js to enable Swagger 2.0 conversion.")
        print("  Continuing with original file.")
        print()
        return path, False
    except subprocess.TimeoutExpired:
        print("  WARNING: swagger2openapi timed out after 120s.")
        print("  Continuing with original file.")
        print()
        return path, False


def load_spec(path):
    """Load an OpenAPI spec from YAML or JSON."""
    text = Path(path).read_text(encoding='utf-8')
    if path.endswith(('.yaml', '.yml')):
        if not HAS_YAML:
            print("ERROR: PyYAML required for YAML files: pip install pyyaml", file=sys.stderr)
            sys.exit(1)
        return yaml.safe_load(text), 'yaml'
    return json.loads(text), 'json'


def save_spec(spec, path, fmt):
    """Save spec to YAML or JSON."""
    if fmt == 'yaml':
        Path(path).write_text(
            yaml.dump(spec, default_flow_style=False, sort_keys=False, allow_unicode=True),
            encoding='utf-8',
        )
    else:
        Path(path).write_text(json.dumps(spec, indent=2) + '\n', encoding='utf-8')


def fix_server_urls(spec):
    """Strip https:// from variable-based URLs, remove default from variables.

    Evidence: 10/10 production Foundry specs with server variables omit https://
    and none use default without enum. Foundry console adds protocol separately.
    """
    changes = []
    for server in spec.get('servers', []):
        url = server.get('url', '')
        variables = server.get('variables', {})

        # Only strip protocol from URLs with variables (Foundry adds it separately)
        # Keep https:// on hardcoded URLs like https://jsonplaceholder.typicode.com
        if variables and re.match(r'^https?://', url):
            old_url = url
            server['url'] = re.sub(r'^https?://', '', url)
            changes.append(
                f"  Stripped protocol: '{old_url}' -> '{server['url']}'"
            )
        # Remove default from variables unless they have enum (enum = real selectable options)
        for var_name, var_config in variables.items():
            if not isinstance(var_config, dict):
                continue
            has_enum = 'enum' in var_config
            if 'default' in var_config and not has_enum:
                del var_config['default']
                changes.append(
                    f"  Removed default from variable '{var_name}'"
                    f" (causes dropdown instead of text field)"
                )

    return changes


def fix_auth(spec):
    """Fix auth schemes for Foundry compatibility.

    Removes oauth2 authorizationCode flows (Foundry only supports clientCredentials).
    Keeps apiKey schemes as-is (Foundry's UI maps apiKey in Authorization header
    to its credential prompt with prefix support).
    """
    changes = []
    schemes = spec.get('components', {}).get('securitySchemes', {})
    # Also check Swagger 2.0 securityDefinitions
    if not schemes:
        schemes = spec.get('securityDefinitions', {})
    to_remove = []

    for name, scheme in list(schemes.items()):
        scheme_type = scheme.get('type', '')

        # apiKey in Authorization header: infer prefix from description
        # Foundry uses bearerFormat for the prefix field even on apiKey schemes
        if (scheme_type == 'apiKey'
                and scheme.get('in', '').lower() == 'header'
                and scheme.get('name', '').lower() == 'authorization'
                and 'bearerFormat' not in scheme):
            desc = scheme.get('description', '')
            prefix_match = re.search(r'\b(SSWS|Bearer|Token|Basic)\s*[\{:]', desc,
                                     re.IGNORECASE)
            if prefix_match:
                prefix = prefix_match.group(1)
                known = {'ssws': 'SSWS', 'bearer': 'Bearer',
                         'token': 'Token', 'basic': 'Basic'}
                bearer_format = known.get(prefix.lower(), prefix)
                scheme['bearerFormat'] = bearer_format
                changes.append(
                    f"  Added bearerFormat: {bearer_format} to '{name}'"
                    f" (inferred from description as API key prefix)"
                )

        # oauth2 with authorizationCode → remove (Foundry doesn't support it)
        if scheme_type == 'oauth2':
            flows = scheme.get('flows', {})
            if 'authorizationCode' in flows and 'clientCredentials' not in flows:
                to_remove.append(name)
                changes.append(
                    f"  Removed '{name}' (oauth2 authorizationCode "
                    f"— Foundry only supports clientCredentials)"
                )

        # Warn about unsupported types
        if scheme_type not in ('http', 'oauth2', 'apiKey'):
            changes.append(
                f"  WARNING: '{name}' has type '{scheme_type}'. "
                f"Foundry supports: http (bearer/basic), oauth2, apiKey"
            )

    # Apply removals
    for name in to_remove:
        del schemes[name]

    # Remove security references to deleted schemes
    if to_remove:
        _replace_security_refs(spec, to_remove, None)
        changes.append(f"  Removed security references: {to_remove}")

    # Ensure a global security block exists if we have any security schemes.
    # Without this, Foundry won't prompt for credentials at install time.
    remaining_schemes = list(schemes.keys())
    if remaining_schemes and 'security' not in spec:
        spec['security'] = [{remaining_schemes[0]: []}]
        changes.append(
            f"  Added global security referencing '{remaining_schemes[0]}'"
            f" (was missing — Foundry requires this for credential prompt)"
        )

    # Remove per-operation 'security: []' overrides that disable auth.
    # These are left behind when vendor specs define per-operation security
    # and the original schemes get removed/replaced.
    if remaining_schemes:
        empty_count = 0
        for path_item in spec.get('paths', {}).values():
            for operation in path_item.values():
                if isinstance(operation, dict) and operation.get('security') == []:
                    del operation['security']
                    empty_count += 1
        if empty_count:
            changes.append(
                f"  Removed {empty_count} empty per-operation security overrides"
                f" (were disabling auth)"
            )

    return changes


def _replace_security_refs(spec, old_names, new_name):
    """Remove (or replace) security scheme references throughout the spec."""
    # Top-level security
    if 'security' in spec:
        spec['security'] = _replace_refs_in_list(spec['security'], old_names, new_name)
        if not spec['security']:
            del spec['security']

    # Per-operation security
    for path_item in spec.get('paths', {}).values():
        for operation in path_item.values():
            if isinstance(operation, dict) and 'security' in operation:
                operation['security'] = _replace_refs_in_list(
                    operation['security'], old_names, new_name
                )


def _replace_refs_in_list(security_list, old_names, new_name):
    """Replace or remove scheme references in a security requirements list."""
    new_list = []
    seen_new = False
    for req in security_list:
        if not isinstance(req, dict):
            new_list.append(req)
            continue
        new_req = {}
        for key, val in req.items():
            if key in old_names:
                if new_name and not seen_new:
                    new_req[new_name] = []
                    seen_new = True
                # else: removing without replacement, just drop the reference
            else:
                new_req[key] = val
        if new_req:
            new_list.append(new_req)
    if not new_list and seen_new and new_name:
        new_list.append({new_name: []})
    return new_list



def _resolve_param_sig(param, components):
    """Resolve a parameter (possibly a $ref) to its (name, in) signature."""
    if not isinstance(param, dict):
        return None
    if '$ref' in param:
        # Resolve #/components/parameters/X
        ref = param['$ref']
        if ref.startswith('#/components/parameters/'):
            ref_name = ref.split('/')[-1]
            resolved = components.get('parameters', {}).get(ref_name, {})
            if 'name' in resolved and 'in' in resolved:
                return (resolved['name'], resolved['in'])
        return None
    if 'name' in param and 'in' in param:
        return (param['name'], param['in'])
    return None


def dedup_parameters(spec):  # pylint: disable=too-many-branches
    """Remove operation-level parameters that duplicate path-level parameters.

    Some vendor specs (e.g., Okta) define the same parameter at both the path
    and operation level — sometimes as $ref, sometimes inline. Foundry's validator
    rejects this as duplicate required items. Resolves $refs before comparing.
    """
    changes = []
    components = spec.get('components', {})

    for path, path_item in spec.get('paths', {}).items():
        if not isinstance(path_item, dict):
            continue
        path_params = path_item.get('parameters', [])
        if not path_params:
            continue

        # Resolve path-level params to (name, in) signatures
        path_sigs = set()
        for p in path_params:
            sig = _resolve_param_sig(p, components)
            if sig:
                path_sigs.add(sig)

        if not path_sigs:
            continue

        for method in ('get', 'post', 'put', 'patch', 'delete', 'options', 'head'):
            op = path_item.get(method)
            if not isinstance(op, dict):
                continue
            op_params = op.get('parameters', [])
            if not op_params:
                continue

            deduped = []
            for p in op_params:
                sig = _resolve_param_sig(p, components)
                if sig and sig in path_sigs:
                    op_id = op.get('operationId', f'{method} {path}')
                    label = p.get('$ref', p.get('name', '?'))
                    changes.append(f"  Removed duplicate param '{label}' from {op_id}")
                    continue
                deduped.append(p)

            if len(deduped) != len(op_params):
                if deduped:
                    op['parameters'] = deduped
                else:
                    del op['parameters']

    return changes


def validate_operation_config(spec):
    """Validate x-cs-operation-config structure (expose_to_workflow must be under workflow: key).

    Does not fix — this requires prompt-driven decisions about operation names and descriptions.
    Returns warnings for the agent to act on.
    """
    warnings = []
    for path, path_item in spec.get('paths', {}).items():
        if not isinstance(path_item, dict):
            continue
        for method in ('get', 'post', 'put', 'patch', 'delete', 'options', 'head'):
            op = path_item.get(method)
            if not isinstance(op, dict):
                continue
            cfg = op.get('x-cs-operation-config')
            if not isinstance(cfg, dict):
                continue
            if cfg.get('expose_to_workflow') is True and 'workflow' not in cfg:
                op_id = op.get('operationId', f'{method} {path}')
                warnings.append(
                    f"  {op_id}: expose_to_workflow is directly under "
                    f"x-cs-operation-config. Must be nested under a 'workflow' "
                    f"key or the endpoint won't appear in Falcon Fusion SOAR."
                )
    return warnings


def main():
    """CLI entry point: parse args and run all transformations."""
    parser = argparse.ArgumentParser(
        description='Transform OpenAPI specs for Falcon Foundry'
    )
    parser.add_argument('input', help='Input OpenAPI spec (YAML or JSON)')
    parser.add_argument('-o', '--output', help='Output path (default: overwrite input)')
    parser.add_argument(
        '--no-convert', action='store_true',
        help='Skip Swagger 2.0 → OpenAPI 3.0 conversion'
    )
    parser.add_argument(
        '--dry-run', action='store_true',
        help='Show changes without writing'
    )
    args = parser.parse_args()

    input_path = args.input

    # 0. Convert Swagger 2.0 → OpenAPI 3.0 if needed
    if not args.no_convert:
        input_path, converted = convert_swagger_to_openapi(input_path)
        if converted and not args.output:
            # Use the converted file as both input and output
            args.output = input_path

    spec, fmt = load_spec(input_path)
    output_path = args.output or args.input

    print(f"Adapting {input_path} for Falcon Foundry...")
    print()

    # 1. Fix server URLs
    changes = fix_server_urls(spec)
    if changes:
        print("Server URLs:")
        for c in changes:
            print(c)
        print()

    # 2. Fix auth schemes
    changes = fix_auth(spec)
    if changes:
        print("Authentication:")
        for c in changes:
            print(c)
        print()

    # 3. Remove duplicate parameters
    changes = dedup_parameters(spec)
    if changes:
        print("Parameters:")
        for c in changes:
            print(c)
        print()

    # 4. Validate operation config structure (warn only, no auto-fix)
    warnings = validate_operation_config(spec)
    if warnings:
        print("Operation config warnings:")
        for w in warnings:
            print(w)
        print()

    if args.dry_run:
        print("(dry run - no files written)")
    else:
        save_spec(spec, output_path, fmt)
        print(f"Saved: {output_path}")


if __name__ == '__main__':
    main()
