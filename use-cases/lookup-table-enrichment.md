---
name: lookup-table-enrichment
description: Upload third-party data as a lookup table in Falcon Next-Gen SIEM for automated event enrichment and threat hunting
source: https://www.crowdstrike.com/tech-hub/ng-siem/falcon-next-gen-siem-creating-a-lookup-table-with-3rd-party-data-for-automated-enrichment/
skills: [foundry-collections-development, foundry-functions-development, foundry-workflows-development]
capabilities: [collection, function, workflow]
---

## When to Use

User wants to enrich Falcon sensor events with external threat intelligence or reference data, create lookup tables from third-party sources (threat feeds, asset inventories, IP reputation lists), match network events against known-bad indicators, or visualize matched events on a world map.

## Pattern

### 1. Generate a CSV from External Data

Write a script to fetch and transform the external data into CSV format. The CSV becomes a lookup file in Falcon Next-Gen SIEM.

Example: converting Spamhaus ASN-DROP (known-bad Autonomous System Numbers) JSON feed to CSV.

```python
import pandas as pd

df = pd.read_json("https://www.spamhaus.org/drop/asndrop.json", lines=True)

# Drop metadata row and its columns
df = df.iloc[:-1]
df = df.drop(columns=['type', 'timestamp', 'size', 'records', 'copyright', 'terms'])

df["asn"] = df["asn"].astype(int)
df.to_csv('asndrop.csv', index=False)
```

### 2. Upload as a Lookup File

1. Log in to Falcon > Next-Gen SIEM > Lookup files.
2. Click Create file > Import file.
3. Select the CSV and import.

### 3. Query Events Against the Lookup Table

Use CQL (CrowdStrike Query Language) to match sensor events against the lookup file.

**Table view** -- match network connections against known-bad ASNs:
```sql
#type=falcon-raw-data
| #event_simpleName = NetworkConnectIP4
| asn(field=RemoteAddressIP4, as=ASN)
| match(file="asndrop.csv", field=[ASN.asn], column=asn)
| table([ComputerName, aid, RemoteAddressIP4, ASN.asn, domain, cc])
```

**World map visualization** -- replace the `table()` line with:
```sql
| worldMap(ip=RemoteAddressIP4)
```

### 4. Operationalize the Results

Save the query as a:
- **Scheduled search** -- runs on a recurring basis, generates alerts.
- **Dashboard widget** -- adds to a custom dashboard for ongoing monitoring.
- **Export** -- download results as a file for reporting.

## Key Code

```python
# Minimal CSV generation pattern for any JSON API feed
import pandas as pd

df = pd.read_json("https://example.com/feed.json", lines=True)
# Clean columns, cast types as needed
df.to_csv('lookup.csv', index=False)
```

```sql
-- CQL pattern: match events against a lookup file
#type=falcon-raw-data
| #event_simpleName = NetworkConnectIP4
| asn(field=RemoteAddressIP4, as=ASN)
| match(file="lookup.csv", field=[ASN.asn], column=asn)
| table([ComputerName, aid, RemoteAddressIP4, ASN.asn, domain, cc])
```

```sql
-- CQL pattern: query Okta events from ingested data
#repo="okta" #Vendor="okta" #event.module="sso"
| #event.kind="event"
| event.action="user.lifecycle.create"
| table([user.target.full_name, user.target.name, message, @timestamp], limit=1000)
```

## Gotchas

- **World map "Incompatible" error**: The `worldMap()` function needs an IP field directly, not a `table()` output. Remove the `table()` line and use `worldMap(ip=<field>)` instead.
- **CQL comments**: Use `//` prefix to comment out a line in CQL queries.
- **Lookup file size limits**: Large CSV files may impact query performance. Keep lookup files focused on the specific indicators you need.
- **Virtual environment for Python**: If you see `ModuleNotFoundError: No module named 'pandas'`, activate your virtual environment with `source .venv/bin/activate`.
- **Automation opportunity**: The CSV generation script can be wrapped in a Foundry Function (Python) and triggered by a scheduled workflow to keep the lookup table current automatically.
- **Data freshness**: Lookup files are static once uploaded. For dynamic enrichment, consider a Foundry Function that calls the API at query time, or schedule periodic re-uploads via workflow.
