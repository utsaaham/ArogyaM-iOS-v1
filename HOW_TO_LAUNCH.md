# How to launch

## Requirements

- Xcode on macOS.
- A physical iPhone.
- Apple Health data on the phone.
- Apple Developer signing set up for the project.

HealthKit data is not available in the iOS Simulator, so use a real device.

## 1. Open the project

Open:

```text
ArogyaM-iOS-v1.xcodeproj
```

in Xcode.

## 2. Set signing

1. Select the app target.
2. Open **Signing & Capabilities**.
3. Select your Apple Developer team.
4. Make sure HealthKit capability is enabled.

## 3. Configure the server

Use the app settings or `.env` values for:

```dotenv
BASE_URL=http://192.168.1.194:30000
USERNAME=your-arogyamandiram-username
BEARER_TOKEN=your-connector-api-token
```

The `BASE_URL` should not have a trailing slash.

## 4. Run on iPhone

1. Connect your iPhone.
2. Select the physical device in Xcode.
3. Press **Run**.
4. Grant Health permissions when iOS asks.

## 5. Test a push

1. Open the Health screen in the app.
2. Tap **Refresh**.
3. Confirm data appears.
4. Tap **Send**.
5. Check ArogyaMandiram **Settings → Connectors** for last sync status.
