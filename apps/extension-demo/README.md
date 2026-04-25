# DreamWork Demo Extension

This is a lightweight Chrome MV3 demo extension for local autofill from `core-api`.

## Load in Chrome

1. Open `chrome://extensions`
2. Enable **Developer mode**
3. Click **Load unpacked**
4. Select folder: `apps/extension-demo`

## Use

1. Ensure `core-api` is running and port-forwarded on `127.0.0.1:18081`.
2. Open `demo/form/demo-form.html` in browser (via local HTTP server).
3. Click extension icon.
4. Click **Seed Person in Core API**.
5. Click **Fill Active Form**.

The form fields should populate with demo values.
