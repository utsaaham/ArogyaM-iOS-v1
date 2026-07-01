# How to connect

Use this app with the **ArogyaM Mobile App Connector** in ArogyaMandiram.

## 1. Open the connector in ArogyaMandiram

1. Open ArogyaMandiram in your browser.
2. Go to **Settings**.
3. Open **Connectors**.
4. Find **ArogyaM Mobile App Connector**.

## 2. Set the connector values

In ArogyaMandiram, save:

- **Connector endpoint URL**
  - Format: `<BASE_URL>/api/health-snapshots/<USERNAME>`
  - Example: `http://192.168.1.194:30000/api/health-snapshots/kiran`
- **Connector API token**
  - This token is sent by the iOS app as `Authorization: Bearer <token>`.

## 3. Add the same values in the iOS app

In the iOS app, set:

- Backend base URL: the same server used by ArogyaMandiram.
- Health username: your ArogyaMandiram username.
- Health API key: the connector API token saved in ArogyaMandiram.

The app sends data to:

```text
<BASE_URL>/api/health-snapshots/<USERNAME>
```

## 4. Send health data

1. Grant Health permissions on the iPhone.
2. Tap **Refresh** in the iOS app.
3. Review the health snapshot.
4. Tap **Send**.
5. In ArogyaMandiram, use **Sync Now** or auto-sync to pull the latest connector data into logs.
