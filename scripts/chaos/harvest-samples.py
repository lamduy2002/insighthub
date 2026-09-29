#!/usr/bin/env python3
"""Harvest RCA `samples` verbatim from Prometheus so nobody types telemetry by hand.

Uses the same call as scripts/verify.py:622-633 (GET /api/v1/query_range, exact label
selector, start=at end=at+1 step=1) and re-checks every sample with that exact rule
(|ts - at| < 1s, isclose rel_tol=1e-6 / abs_tol=1e-9) before printing it.

  harvest-samples.py --metric insighthub_documents_total --label status=pending \
      --start 2026-09-29T14:00:00Z --end 2026-09-29T14:10:00Z --select max

Output: {"samples": [{"metric", "labels", "timestamp", "value"}, ...]} on stdout, ready to
paste into an RCA JSON. Labels come from the returned series (minus __name__), so the
selector the verifier rebuilds matches the same series.
"""
import argparse
import datetime as dt
import json
import math
import os
import re
import sys
import urllib.parse
import urllib.request

NAME = re.compile(r"[a-zA-Z_:][a-zA-Z0-9_:]*")
LABEL = re.compile(r"[a-zA-Z_][a-zA-Z0-9_]*")


def rfc3339(value):
    parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise SystemExit("timestamp needs a timezone: " + value)
    return parsed.timestamp()


def fmt(ts):
    return dt.datetime.fromtimestamp(ts, dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def selector(metric, labels):
    # Identical construction to verify.py:622.
    return metric + ("{" + ",".join(k + "=" + json.dumps(v) for k, v in sorted(labels.items())) + "}" if labels else "")


def query_range(base, query, start, end, step, timeout):
    url = base + "/api/v1/query_range?" + urllib.parse.urlencode(
        {"query": query, "start": start, "end": end, "step": step})
    with urllib.request.build_opener().open(url, timeout=timeout) as response:
        body = json.load(response)
    if body.get("status") != "success" or body["data"].get("resultType") != "matrix":
        raise SystemExit("Prometheus did not return range data for: " + query)
    return body["data"]["result"]


def verifier_accepts(base, metric, labels, at, value, timeout):
    """Replays the verifier's check for one sample (verify.py:622-633)."""
    for series in query_range(base, selector(metric, labels), at, at + 1, 1, timeout):
        for ts, val in series.get("values", []):
            if abs(float(ts) - at) < 1 and math.isclose(float(val), value, rel_tol=1e-6, abs_tol=1e-9):
                return True
    return False


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--metric", required=True)
    ap.add_argument("--label", action="append", default=[], metavar="K=V", help="exact-match label, repeatable")
    ap.add_argument("--start", required=True, help="RFC3339 with timezone")
    ap.add_argument("--end", required=True, help="RFC3339 with timezone")
    ap.add_argument("--step", type=int, default=30, help="seconds between candidate samples (default 30)")
    ap.add_argument("--select", choices=["all", "max", "min", "first", "last"], default="all",
                    help="per series: keep every candidate, or only the max/min/first/last one")
    ap.add_argument("--limit", type=int, default=0, help="thin to at most N samples per series, evenly spaced")
    ap.add_argument("--prometheus-url", default=os.environ.get("PROMETHEUS_URL", "http://localhost:9090"))
    ap.add_argument("--timeout", type=float, default=10)
    ap.add_argument("--no-verify", action="store_true", help="skip the verifier replay (not recommended)")
    args = ap.parse_args()

    if not NAME.fullmatch(args.metric):
        raise SystemExit("invalid metric name")
    labels = {}
    for item in args.label:
        key, sep, value = item.partition("=")
        if not sep or not LABEL.fullmatch(key):
            raise SystemExit("invalid --label, expected K=V: " + item)
        labels[key] = value
    start, end = rfc3339(args.start), rfc3339(args.end)
    if not start < end:
        raise SystemExit("--start must be before --end")
    start = math.ceil(start)  # whole seconds keep timestamps exact through RFC3339
    base = args.prometheus_url.rstrip("/")

    samples, rejected = [], 0
    for series in query_range(base, selector(args.metric, labels), start, end, args.step, args.timeout):
        series_labels = {k: v for k, v in series["metric"].items() if k != "__name__"}
        points = []
        for ts, raw in series["values"]:
            value = float(raw)
            if math.isfinite(value):  # verify.py's load_json rejects NaN/Inf
                points.append((int(float(ts)), value))
        if not points:
            continue
        if args.select == "max":
            points = [max(points, key=lambda p: p[1])]
        elif args.select == "min":
            points = [min(points, key=lambda p: p[1])]
        elif args.select == "first":
            points = points[:1]
        elif args.select == "last":
            points = points[-1:]
        elif args.limit and len(points) > args.limit:
            idx = sorted({round(i * (len(points) - 1) / max(args.limit - 1, 1)) for i in range(args.limit)})
            points = [points[i] for i in idx]
        for at, value in points:
            if not args.no_verify and not verifier_accepts(base, args.metric, series_labels, at, value, args.timeout):
                rejected += 1
                continue
            samples.append({"metric": args.metric, "labels": series_labels,
                            "timestamp": fmt(at), "value": value})
    if not samples:
        raise SystemExit("no samples harvested (metric absent in window, or all rejected by verifier replay)")
    if rejected:
        print(f"warning: {rejected} candidate(s) failed the verifier replay and were dropped", file=sys.stderr)
    json.dump({"samples": samples}, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
