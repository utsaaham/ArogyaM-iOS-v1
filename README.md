# ArogyaM (ArogyaM-iOS-v1)

A lightweight iOS app that reads your Apple Health data for the past week and sends a clean, structured JSON payload to a backend of your choice.

Built with **SwiftUI** and **HealthKit**, ArogyaM extracts a daily snapshot of heart rate, activity, sleep, and workouts — for today plus the previous 7 days — and lets you review it on-device before pushing it to an HTTP API with a single tap.

---

## Features

- **Weekly extraction** — Pulls 8 daily snapshots (today + 7 prior days) in parallel for fast loading.
- **Rich metrics per day:**
  - ❤️ Average heart rate (BPM)
  - 🚶 Steps, active calories, and walking/running distance
  - 😴 Sleep with stage breakdown (core / deep / REM / awake), bedtime, and wake time
  - 🏃 Workouts with type, duration, calories, distance, and average heart rate
- **Connector detection** — Lists the data sources feeding HealthKit (e.g. Apple Watch, iPhone).
- **Review before send** — Inspect the full week in the UI, then POST it to your server.
- **Clear error reporting** — Network and HTTP errors surface as readable, actionable messages.

---

## How it works

```
┌──────────────┐     read      ┌─────────────┐    POST JSON    ┌──────────────┐
│  HealthKit    │ ───────────▶ │   ArogyaM     │ ──────────────▶ │  Your backend │
│  (on device)  │              │  (SwiftUI)   │   + Bearer auth │   /send-data  │
└──────────────┘              └─────────────┘                  └──────────────┘
```

1. On launch, the app requests read authorization for the relevant HealthKit types.
2. `Refresh` fetches per-day statistics via `HKStatisticsQuery` / `HKSampleQuery`, running each day concurrently with `withTaskGroup`.
3. The result is assembled into a `WeeklyHealthPayload` and rendered in the UI.
4. `Send` encodes the payload to JSON and `POST`s it to the configured endpoint with a Bearer token.

---

## Project structure

| File | Responsibility |
|------|----------------|
| `ArogyaM_iOS_v1App.swift` | App entry point (`@main`). |
| `ContentView.swift` | SwiftUI UI — "Today" and "Last Week" sections, connectors list, Refresh/Send actions. |
| `HealthKitService.swift` | All HealthKit access: authorization, per-day fetchers, sleep/workout aggregation, source detection. |
| `APIClient.swift` | Network layer — encodes and POSTs the payload; maps transport/HTTP errors to readable messages. |
| `Models.swift` | `Codable` data model for the payload (`WeeklyHealthPayload`, `HealthSnapshot`, metrics structs). |
| `Config.swift` | Loads backend URL, endpoints, and Bearer token from the bundled `.env`. |
| `.env` / `.env.example` | Runtime config (git-ignored secret) and its committed template. |
| `Info.plist` / `*.entitlements` | HealthKit entitlement and local-network usage description. |

---

## Configuration

Configuration lives in a **`.env` file** that is git-ignored and bundled into the
app at build time — secrets stay out of source control.

1. Copy the template and fill in your values:

   ```bash
   cp ArogyaM-iOS-v1/.env.example ArogyaM-iOS-v1/.env
   ```

2. Edit `ArogyaM-iOS-v1/.env`:

   ```dotenv
   # Sent as: Authorization: Bearer <token>
   BEARER_TOKEN=your-bearer-token-here

   # Backend base URL (no trailing slash)
   BASE_URL=http://192.168.1.194:30001     # local dev
   # BASE_URL=https://your-app.vercel.app  # production
   ```

`Config.swift` reads these at runtime via a small `.env` parser
(`Config.bearerToken`, `Config.baseURL`), falling back to process environment
variables (e.g. an Xcode scheme env var, handy for CI). A missing key triggers a
clear `fatalError` rather than shipping a wrong value.

> ⚠️ **Security notes:**
> - `.env` is git-ignored (see `.gitignore`); `.env.example` is the committed template.
> - The `.env` is bundled inside the app, so the token still ships within the
>   binary and can be extracted by a determined attacker. Treat it as a shared
>   API key, not a user secret, and **rotate the previously committed token**.

The app sends a `POST` to `sendDataURL` with:

- `Content-Type: application/json`
- `Authorization: Bearer <token>`

A `200` response indicates success; any other status is reported as an error.

---

## Payload format

```json
{
  "extractedAt": "2026-06-20T14:32:00Z",
  "days": [
    {
      "date": "2026-06-20",
      "today": true,
      "heart": { "avgBpm": 72 },
      "activity": { "steps": 8421, "activeCalories": 540, "distanceKm": 6.12 },
      "sleep": {
        "totalHours": 7.4,
        "stages": { "awakeHours": 0.3, "coreHours": 4.1, "deepHours": 1.2, "remHours": 2.1 },
        "bedtime": "2026-06-19T23:10:00Z",
        "wake": "2026-06-20T06:45:00Z"
      },
      "workouts": [
        {
          "uuid": "…",
          "type": "Running",
          "durationMin": 32,
          "calories": 310,
          "distanceKm": 5.04,
          "avgHeartRate": 148,
          "startedAt": "2026-06-20T07:00:00Z",
          "endedAt": "2026-06-20T07:32:00Z"
        }
      ]
    }
  ]
}
```

Notes:
- `days[]` contains today plus the previous 7 days. The current day is flagged with `"today": true`.
- `heart.avgBpm`, `sleep`, and per-metric values may be `null`/absent when no data exists for that day.
- Times are ISO 8601; `date` is a local calendar day (`yyyy-MM-dd`).

---

## Requirements

- **Xcode** (recent version) and a Mac
- **iOS deployment target:** 26.4
- **Swift:** 5.0
- A **physical iOS device** with Health data — HealthKit data is not available in the Simulator
- An Apple Developer account/team for code signing (HealthKit requires a provisioned device)

---

## Getting started

1. Open `ArogyaM-iOS-v1.xcodeproj` in Xcode.
2. Set your signing team under **Signing & Capabilities** (HealthKit must be enabled).
3. Update `Config.swift` with your backend URL and token.
4. Select a physical device and run.
5. Grant the requested Health permissions when prompted.
6. Tap **Refresh** to extract the week, review the data, then **Send** to push it to your backend.

---

## HealthKit data types

The app requests **read-only** access to:

- Heart rate
- Step count
- Active energy burned
- Walking + running distance
- Sleep analysis
- Workouts

It never requests write/share access.

---

## License

No license file is currently included. Add one if you intend to distribute or open-source this project.
