# Go Function Patterns Reference

> Parent skill: [functions-development](../SKILL.md)

## FDK Handler with Configuration

Load configuration from `config.json` or `config.yaml` in the function directory. The config type must implement `OK() error`, which the FDK calls to validate it:

```go
func newHandler(_ context.Context, _ *slog.Logger, cfg myConfig) fdk.Handler {
    // cfg is loaded from config.json or config.yaml in the function directory
    m := fdk.NewMux()
    // ... use cfg in handlers
    return m
}
```

## Alerts Handler with Falcon Client Auth

`PostCombinedAlertsV1` queries and returns alerts in one call. The FDK hands the caller's token to the handler as `r.AccessToken`; build the gofalcon client from it inside the handler with `fdk.FalconClientOpts()` (the pattern foundry-sample-anomali-threatstream uses). Return failures with `fdk.ErrResp(fdk.APIError{...})`:

```go
// functions/alerts/main.go
package main

import (
    "context"
    "log/slog"
    "net/http"

    fdk "github.com/CrowdStrike/foundry-fn-go"
    "github.com/crowdstrike/gofalcon/falcon"
    "github.com/crowdstrike/gofalcon/falcon/client"
    "github.com/crowdstrike/gofalcon/falcon/client/alerts"
    "github.com/crowdstrike/gofalcon/falcon/models"
)

type alertsReq struct {
    Filter string `json:"filter"`
    Limit  int32  `json:"limit"`
}

func main() {
    fdk.Run(context.Background(), newHandler)
}

func newHandler(_ context.Context, logger *slog.Logger, _ fdk.SkipCfg) fdk.Handler {
    m := fdk.NewMux()
    m.Post("/alerts", fdk.HandleFnOf(func(ctx context.Context, r fdk.RequestOf[alertsReq]) fdk.Response {
        limit := r.Body.Limit
        if limit == 0 {
            limit = 50
        }
        if limit < 0 || limit > 100 {
            return fdk.ErrResp(fdk.APIError{Code: http.StatusBadRequest, Message: "limit must be between 1 and 100"})
        }

        falconClient, err := newFalconClient(ctx, r.AccessToken)
        if err != nil {
            logger.Error("failed to create Falcon client", "error", err)
            return fdk.ErrResp(fdk.APIError{Code: http.StatusInternalServerError, Message: falcon.ErrorExplain(err)})
        }

        params := alerts.NewPostCombinedAlertsV1Params().
            WithContext(ctx).
            WithBody(&models.DetectsapiPostCombinedAlertsV1RequestSwagger{
                Filter: r.Body.Filter,
                Limit:  limit,
            })
        resp, err := falconClient.Alerts.PostCombinedAlertsV1(params)
        if err != nil {
            logger.Error("alerts query failed", "error", err)
            return fdk.ErrResp(fdk.APIError{Code: http.StatusBadGateway, Message: falcon.ErrorExplain(err)})
        }
        if err := falcon.AssertNoError(resp.Payload.Errors); err != nil {
            return fdk.ErrResp(fdk.APIError{Code: http.StatusBadGateway, Message: err.Error()})
        }

        return fdk.Response{
            Code: http.StatusOK,
            Body: fdk.JSON(map[string]any{"alerts": resp.Payload.Resources}),
        }
    }))
    return m
}

func newFalconClient(ctx context.Context, accessToken string) (*client.CrowdStrikeAPISpecification, error) {
    opts := fdk.FalconClientOpts()
    return falcon.NewClient(&falcon.ApiConfig{
        AccessToken:       accessToken,
        Cloud:             falcon.Cloud(opts.Cloud),
        Context:           ctx,
        UserAgentOverride: opts.UserAgent,
    })
}
```

`HandleFnOf` decodes the request body into `alertsReq` and returns a 400 if it can't, so callers send a JSON body (`{}` is enough). Read query parameters from `r.Queries` and headers from `r.Headers`.

## Collection CRUD Pattern

Incident store using `custom_storage` for create, read, and delete operations. It reuses `newFalconClient` from the alerts handler; pass it `r.AccessToken` from the handler's request:

```go
// functions/incidents/collection.go
package main

import (
    "bytes"
    "context"
    "encoding/json"
    "errors"
    "fmt"
    "io"
    "time"

    "github.com/crowdstrike/gofalcon/falcon/client"
    "github.com/crowdstrike/gofalcon/falcon/client/custom_storage"
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
    client     *client.CrowdStrikeAPISpecification
    collection string
}

func NewIncidentStore(ctx context.Context, accessToken string) (*IncidentStore, error) {
    falconClient, err := newFalconClient(ctx, accessToken)
    if err != nil {
        return nil, fmt.Errorf("failed to create falcon client: %w", err)
    }
    return &IncidentStore{client: falconClient, collection: "incidents"}, nil
}

// Create writes the incident under incident.ID (PutObject creates or overwrites)
func (s *IncidentStore) Create(ctx context.Context, incident *Incident) error {
    if incident.ID == "" {
        return errors.New("incident ID is required")
    }
    incident.CreatedAt = time.Now()
    incident.UpdatedAt = incident.CreatedAt

    data, err := json.Marshal(incident)
    if err != nil {
        return fmt.Errorf("failed to marshal incident: %w", err)
    }

    params := custom_storage.NewPutObjectParamsWithContext(ctx)
    params.SetCollectionName(s.collection)
    params.SetObjectKey(incident.ID)
    params.SetBody(io.NopCloser(bytes.NewReader(data)))
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
