# SQL Connection Pool Observability Example

A hands-on example that demonstrates **automatic observability** for
Ballerina's SQL module. The service contains no metric instrumentation code —
pool health, connection event timing, and SQL operation metrics are emitted
automatically by the sql module's HikariCP integration and exported to
Prometheus.

---

## What you get — zero instrumentation

When observability is enabled, every `sql:Client` operation automatically
reports metrics. You write clean business logic; the sql module handles
the rest.

| Category | What is measured | Example metric |
|----------|-----------------|----------------|
| **Pool health** | Active, idle, total connections; utilization ratio | `sql_pool_active_connections` |
| **Connection events** | Acquisition wait, usage hold, physical creation time | `sql_connection_acquisition_time_seconds` |

All metrics are tagged with `pool_name` and supplementary database tags
(`db_host`, `db_port`, `db_name`) when provided by the database module.

---

## Architecture

```
                         ┌─────────────────────────┐
   curl / browser  ───▶  │    Ballerina Service     │
                         │    (HTTP :8080)          │
                         │                         │
                         │  sql:Client              │
                         │    └─ HikariCP pool      │
                         │        ├─ pool health    │
                         │        └─ conn events    │
                         └──────┬───────────┬───────┘
                                │           │
                    SQL queries │           │ metrics
                    (JDBC)      │           │ (:9797)
                                ▼           ▼
                         ┌────────────┐ ┌────────────┐
                         │ PostgreSQL │ │ Prometheus  │
                         │  :5433     │ │ :9090       │
                         └────────────┘ └────────────┘
```

**Ballerina** serves HTTP requests and queries PostgreSQL via the sql module.
The sql module's HikariCP integration automatically registers metrics with
Ballerina's observe module. **Prometheus** scrapes the metrics endpoint
(port 9797) every 10 seconds.

---

## Prerequisites

- **Ballerina** 2201.13.0 or later
- **[Colima](https://github.com/abiosoft/colima)** — provides the Docker
  engine and CLI on macOS. Install with
  `brew install colima docker docker-compose`.
- **curl** (or any HTTP client)

---

## Setup

### 1. Start Colima

```bash
colima start
```

### 2. Start the containers

From this directory (`examples/observability/`):

```bash
docker-compose up -d
```

This starts two containers:

| Container | Image | Port |
|-----------|-------|------|
| `observe-postgres` | `postgres:16-alpine` | `5433` -> `5432` |
| `observe-prometheus` | `prom/prometheus` | `9090` -> `9090` |

PostgreSQL initializes the schema automatically from `init.sql` on first start.

### 3. Run the Ballerina service

```bash
bal run
```

You should see output like:

```
ballerina: started Prometheus HTTP listener 0.0.0.0:9797
ballerina: started HTTP/WS listener 0.0.0.0:8080
```

The first line confirms that Prometheus metrics are being exposed.

---

## Try the API

Make a few requests to generate metric data:

```bash
# List all students (uses query)
curl http://localhost:8080/api/students

# Get a single student (uses queryRow)
curl http://localhost:8080/api/students/1

# Create a student (uses execute)
curl -X POST http://localhost:8080/api/students \
  -H "Content-Type: application/json" \
  -d '{"first_name": "Frank", "last_name": "Miller", "age": 24}'

# Delete a student (uses execute)
curl -X DELETE http://localhost:8080/api/students/6

# Trigger a 404 (uses queryRow — recorded as error)
curl -i http://localhost:8080/api/students/999
```

---

## Explore the Built-in Metrics

Open the Prometheus UI at [http://localhost:9090](http://localhost:9090).
This is where you query, graph, and explore all metrics. Paste any of the
PromQL expressions below into the query bar and click **Execute** (or
switch to the **Graph** tab for time-series visualization).

> **Metric naming:** Ballerina's Prometheus reporter appends `_value` to
> gauge and counter names. Summary metrics (timing distributions) use the
> base metric name with a `quantile` label and include a `timeWindow`
> label indicating the sliding window duration in milliseconds.

---

### Pool health metrics

Snapshot gauges showing the current state of the HikariCP connection pool.
Updated on every connection event (borrow, return, timeout).

| What | PromQL | Description |
|------|--------|-------------|
| Active connections | `sql_pool_active_connections_value` | Connections currently borrowed from pool |
| Idle connections | `sql_pool_idle_connections_value` | Connections available in pool |
| Total connections | `sql_pool_total_connections_value` | Active + idle (current pool size) |
| Pending requests | `sql_pool_pending_requests_value` | Threads waiting for a connection |
| Max connections | `sql_pool_max_connections_value` | Configured maximum pool size |
| Min connections | `sql_pool_min_connections_value` | Configured minimum idle connections |
| Utilization | `sql_pool_utilization_ratio_value` | Active / max (0.0 to 1.0) |
| Init time | `sql_pool_initialization_time_seconds_value` | Time to start the pool |

---

### Connection event metrics

Timing of connection lifecycle events. Acquisition and usage times are
summarized with percentiles (p50, p75, p95, p99) over a 10-minute window.

| What | PromQL | Description |
|------|--------|-------------|
| Acquisition wait (mean) | `sql_connection_acquisition_time_seconds_mean` | Average time waiting to get a connection |
| Acquisition wait (p99) | `sql_connection_acquisition_time_seconds{quantile="0.99"}` | Worst-case connection wait |
| Usage hold (mean) | `sql_connection_usage_time_seconds_mean` | Average time a connection is held |
| Creation time (mean) | `sql_connection_creation_time_seconds_mean` | Average physical connection creation time |
| Timeouts | `sql_connection_timeout_total_value` | Total connection acquisitions that timed out |

---

### Diagnostic PromQL queries

These queries help diagnose common database performance issues:

| Query | What it tells you |
|-------|-------------------|
| `sql_pool_utilization_ratio_value > 0.8` | Pool is running hot — consider increasing max size |
| `sql_pool_pending_requests_value > 0` | Threads are waiting for connections — pool too small or queries too slow |
| `rate(sql_connection_timeout_total_value[5m]) > 0` | Connections timing out — pool exhaustion |
| `sql_connection_acquisition_time_seconds{quantile="0.99"}` | How long the slowest 1% wait for a connection |

---

### Quick verification (CLI)

For a quick check without the browser, you can inspect the raw metrics
endpoint directly. The output mixes HTTP framework metrics with SQL
metrics, so filter with grep:

```bash
curl -s http://localhost:9797/metrics | grep "^sql_"
```

---

## Understanding the Code

### No instrumentation needed

Look at `main.bal` — it is pure business logic. There are no metric
declarations, no timing calls, no counter increments. The service just
uses `sql:Client` methods (`query`, `queryRow`, `execute`) and the sql
module handles all metric reporting internally.

### How it works

When the connection pool starts, the sql module registers a
`MetricsTrackerFactory` with HikariCP. This registers pool health gauges
and captures connection lifecycle events (acquisition wait, usage hold,
physical creation, timeouts). All metrics are registered with Ballerina's
observe module and exported by whichever reporter is configured
(Prometheus in this example).

Database-specific modules (like `ballerinax/postgresql`) provide
supplementary metric tags (`db_host`, `db_port`, `db_name`) from their
client constructor parameters. Generic JDBC clients that only have a URL
will have the `pool_name` tag.

### Enabling observability

Two settings are required:

**Ballerina.toml** — include the observability framework at compile time:
```toml
[build-options]
observabilityIncluded = true
```

**Config.toml** — enable metrics and select the Prometheus reporter:
```toml
[ballerina.observe]
metricsEnabled = true
metricsReporter = "prometheus"

[ballerinax.prometheus]
port = 9797
host = "0.0.0.0"
```

The `import ballerinax/prometheus as _` in `main.bal` ensures the
Prometheus reporter module is loaded at runtime.

---

## Cleanup

Stop and remove the containers:

```bash
docker-compose down
```

Stop the Ballerina service with `Ctrl+C`.
