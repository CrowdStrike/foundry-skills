# Action Discovery Reference

> Parent skill: [workflows-development](../SKILL.md)

## API Query Script for Platform Actions

When `foundry workflows actions view --name "..."` does not find what is needed, query the API directly using credentials from `~/.config/foundry/configuration.yml`:

```bash
# 1. Read credentials from the active Foundry profile
PROFILE=$(python3 -c "
import yaml, sys
with open('$HOME/.config/foundry/configuration.yml') as f:
    cfg = yaml.safe_load(f)
active = cfg.get('active_profile', cfg['profiles'][0]['name'])
p = next(p for p in cfg['profiles'] if p['name'] == active)
region = p.get('cloud_region', 'us-1') or 'us-1'
urls = {'us-1':'api.crowdstrike.com','us-2':'api.us-2.crowdstrike.com',
        'eu-1':'api.eu-1.crowdstrike.com','us-gov-1':'api.laggar.gcw.crowdstrike.com'}
print(f'{urls.get(region, urls[\"us-1\"])}|{p[\"credentials\"][\"api_client_id\"]}|{p[\"credentials\"][\"api_client_secret\"]}')
")
API_HOST=$(echo $PROFILE | cut -d'|' -f1)
CLIENT_ID=$(echo $PROFILE | cut -d'|' -f2)
CLIENT_SECRET=$(echo $PROFILE | cut -d'|' -f3)

# 2. Get OAuth token
TOKEN=$(curl -s -X POST "https://$API_HOST/oauth2/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# 3. Search actions by name (fuzzy match)
curl -s "https://$API_HOST/workflows/combined/activities/v1?filter=name%3A~%27send+email%27&sort=name&limit=20" \
  -H "Authorization: Bearer $TOKEN" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f'{r[\"id\"]}: {r[\"name\"]}') for r in d['resources']]"

# 4. Or list all actions (paginated, 9000+ available)
curl -s "https://$API_HOST/workflows/combined/activities/v1?sort=name&limit=50&offset=0" \
  -H "Authorization: Bearer $TOKEN" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Total: {d[\"meta\"][\"pagination\"][\"total\"]}'); [print(f'{r[\"id\"]}: {r[\"name\"]}') for r in d['resources']]"
```

## Charlotte AI Integration

Workflows can invoke Charlotte AI (CrowdStrike's LLM) as a workflow action. Use `foundry workflows actions view --name "charlotte"` to discover the action ID and its input schema (model, prompt, temperature, json_schema), then reference it like any other action with `id:` + `version_constraint:`.

## CEL Expressions and Variable Injection

CEL handles data transformation and field access; all variable references use `${data['...']}` syntax (NOT `${steps.*.output}` or `${secrets.*}`, which do not resolve). For the full pattern catalog — null-safe access, the `has()` vs `!= null` distinction, optionals, and CrowdStrike extensions — see [cel-expressions.md](cel-expressions.md).
