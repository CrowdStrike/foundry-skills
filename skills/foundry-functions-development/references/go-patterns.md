# Go Function Patterns Reference

> Parent skill: [foundry-functions-development](../SKILL.md)

## FDK Handler with Configuration

Load configuration from `config.json` or `config.yaml` in the function directory:

```go
func newHandler(_ context.Context, _ *slog.Logger, cfg myConfig) fdk.Handler {
    // cfg is loaded from config.json or config.yaml in the function directory
    m := fdk.NewMux()
    // ... use cfg in handlers
    return m
}
```

## Alerts Handler with Falcon Client Auth and Response Helpers

Full alerts handler using the older `http.Handler` pattern with explicit Falcon client setup:

```go
// functions/alerts/main.go
package main

import (
    "context"
    "encoding/json"
    "fmt"
    "net/http"
    "os"

    "github.com/crowdstrike/gofalcon/falcon"
    "github.com/crowdstrike/gofalcon/falcon/client"
    "github.com/crowdstrike/gofalcon/falcon/client/alerts"
    fdk "github.com/CrowdStrike/foundry-fn-go"
)

// Response structures
type APIResponse struct {
    Data    interface{} `json:"data,omitempty"`
    Error   *APIError   `json:"error,omitempty"`
    Status  int         `json:"status"`
}

type APIError struct {
    Code    string `json:"code"`
    Message string `json:"message"`
}

// Handler is the main entry point
func Handler(w http.ResponseWriter, r *http.Request) {
    ctx := r.Context()

    // Validate request method
    if r.Method != http.MethodGet {
        respondError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "Only GET method is supported")
        return
    }

    // Get CrowdStrike client via FDK
    accessToken := r.Header.Get("X-CS-ACCESSTOKEN")
    opts := fdk.FalconClientOpts()
    falconClient, err := falcon.NewClient(&falcon.ApiConfig{
        AccessToken:       accessToken,
        Cloud:             falcon.Cloud(opts.Cloud),
        Context:           ctx,
        UserAgentOverride: opts.UserAgent,
    })
    if err != nil {
        respondError(w, http.StatusInternalServerError, "AUTH_FAILED", "Failed to authenticate with Falcon API")
        return
    }

    // Fetch alerts
    alertsData, err := fetchAlerts(ctx, falconClient, r)
    if err != nil {
        respondError(w, http.StatusInternalServerError, "FETCH_FAILED", err.Error())
        return
    }

    respondSuccess(w, alertsData)
}

func fetchAlerts(ctx context.Context, client *client.CrowdStrikeAPISpecification, r *http.Request) (interface{}, error) {
    // Parse query parameters
    limit := int64(50)
    if l := r.URL.Query().Get("limit"); l != "" {
        fmt.Sscanf(l, "%d", &limit)
        if limit > 100 {
            limit = 100 // Cap at 100
        }
    }

    // Query alerts
    params := alerts.NewQueryAlertsParams().
        WithContext(ctx).
        WithLimit(&limit)

    resp, err := client.Alerts.QueryAlerts(params)
    if err != nil {
        return nil, fmt.Errorf("failed to query alerts: %w", err)
    }

    return resp.Payload, nil
}

func respondSuccess(w http.ResponseWriter, data interface{}) {
    response := APIResponse{
        Data:   data,
        Status: http.StatusOK,
    }
    writeJSON(w, http.StatusOK, response)
}

func respondError(w http.ResponseWriter, status int, code, message string) {
    response := APIResponse{
        Error: &APIError{
            Code:    code,
            Message: message,
        },
        Status: status,
    }
    writeJSON(w, status, response)
}

func writeJSON(w http.ResponseWriter, status int, data interface{}) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(status)
    json.NewEncoder(w).Encode(data)
}

func main() {
    http.HandleFunc("/", Handler)
    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }
    http.ListenAndServe(":"+port, nil)
}
```

## Collection CRUD Pattern

Incident store using `custom_storage` for create, read, and delete operations:

```go
// functions/incidents/collection.go
package main

import (
    "bytes"
    "context"
    "encoding/json"
    "fmt"
    "io"
    "time"

    "github.com/crowdstrike/gofalcon/falcon"
    "github.com/crowdstrike/gofalcon/falcon/client"
    "github.com/crowdstrike/gofalcon/falcon/client/custom_storage"
    fdk "github.com/CrowdStrike/foundry-fn-go"
)

type Incident struct {
    ID          string    `json:"id"`
    Title       string    `json:"title"`
    Severity    int       `json:"severity"`
    Status      string    `json:"status"`
    AssignedTo  string    `json:"assigned_to,omitempty"`
    CreatedAt   time.Time `json:"created_at"`
    UpdatedAt   time.Time `json:"updated_at"`
}

type IncidentStore struct {
    client *client.CrowdStrikeAPISpecification
    collection string
}

func NewIncidentStore(ctx context.Context) (*IncidentStore, error) {
    falconClient, err := falcon.NewClient(fdk.FalconClientOpts())
    if err != nil {
        return nil, fmt.Errorf("failed to create falcon client: %w", err)
    }
    return &IncidentStore{client: falconClient, collection: "incidents"}, nil
}

func (s *IncidentStore) Create(ctx context.Context, incident *Incident) error {
    incident.ID = generateID()
    incident.CreatedAt = time.Now()
    incident.UpdatedAt = time.Now()

    data, err := json.Marshal(incident)
    if err != nil {
        return fmt.Errorf("failed to marshal incident: %w", err)
    }

    params := custom_storage.NewPutObjectParamsWithContext(ctx)
    params.SetCollectionName(s.collection)
    params.SetObjectKey(incident.ID)
    params.SetBody(bytes.NewReader(data))
    _, err = s.client.CustomStorage.PutObject(params)
    return err
}

func (s *IncidentStore) Get(ctx context.Context, id string) (*Incident, error) {
    params := custom_storage.NewGetObjectParamsWithContext(ctx)
    params.SetCollectionName(s.collection)
    params.SetObjectKey(id)

    var buf bytes.Buffer
    _, err := s.client.CustomStorage.GetObject(params, &buf)
    if err != nil {
        return nil, fmt.Errorf("failed to get incident: %w", err)
    }

    var incident Incident
    if err := json.Unmarshal(buf.Bytes(), &incident); err != nil {
        return nil, fmt.Errorf("failed to unmarshal incident: %w", err)
    }

    return &incident, nil
}

func (s *IncidentStore) Delete(ctx context.Context, id string) error {
    params := custom_storage.NewDeleteObjectParamsWithContext(ctx)
    params.SetCollectionName(s.collection)
    params.SetObjectKey(id)
    _, err := s.client.CustomStorage.DeleteObject(params)
    return err
}
```
