# Phase 7.1: Android Dual-Device Testing Guide

This guide describes how to run and verify the Phase 7.1 Secure OTP Delivery Handover using either:
1. Two physical Android devices on the local Wi-Fi network.
2. One physical Android device and one Android emulator.
3. Two independent emulator instances / sequential authenticated sessions.

---

## Prerequisites

1. **Local Backend Running**:
   ```powershell
   Push-Location backend
   npm run build
   npm start
   ```
   Backend listens on port `5000`.

2. **Network Address Resolution**:
   - For Android Emulator: `http://10.0.2.2:5000/api/v1/`
   - For Physical Device: `http://<YOUR_LAN_IP>:5000/api/v1/` (e.g. `http://192.168.1.100:5000/api/v1/`)

---

## Running Flutter on Dual Devices

### Device 1: Customer (Emulator or Phone A)
```powershell
flutter run -d <DEVICE_ID_1> --dart-define=API_BASE_URL=http://<HOST_IP>:5000/api/v1/
```
- Sign in as `customer@demo.test` (password: `Customer#Demo123`).
- Place an order or open an active order.

### Device 2: Delivery Partner / Rider (Phone B or Emulator B)
```powershell
flutter run -d <DEVICE_ID_2> --dart-define=API_BASE_URL=http://<HOST_IP>:5000/api/v1/
```
- Sign in as `rider@demo.test` (password: `Rider#Demo123`).
- Navigate to `/deliveries` ("Your deliveries").

---

## Step-by-Step Handover Verification Workflow

1. **Kitchen & Dispatch Progression**:
   - Order transitions through `ACCEPTED` -> `PREPARING` -> `READY_FOR_PICKUP`.
   - Dispatcher assigns active delivery partner.
   - Rider taps **Confirm pickup** -> Order status becomes `PICKED_UP`.
   - Rider taps **Out for delivery** -> Order status becomes `OUT_FOR_DELIVERY`.

2. **Customer Generates 6-Digit PIN**:
   - On Customer Device, the order detail screen displays the **Secure delivery handover** card.
   - Customer taps **Generate delivery PIN**.
   - Server returns the active 6-digit PIN (e.g. `481920`) with 10-minute expiry countdown.
   - Security advisory is displayed: *"Do not share this PIN over phone or message. Only read it aloud after the delivery partner hands you your sealed package."*

3. **Rider Enters Handover PIN**:
   - On Rider Device, the order card shows **Confirm delivery (PIN)**.
   - Rider taps the button -> **Verify delivery PIN** dialog appears.
   - Rider asks customer for the PIN.
   - If rider enters wrong PIN (e.g. `000000`), server rejects with 400 error and decrements remaining attempts.
   - If 5 incorrect attempts are made, server locks handover and notifies both parties.
   - Rider enters correct 6-digit PIN and taps **Confirm delivery**.

4. **Real-Time Synchronized Confirmation**:
   - Rider dialog closes with success snackbar; order status updates to `DELIVERED`.
   - Customer screen instantly receives WebSocket `order.updated` event.
   - Customer handover card displays **Handover verified** with green checkmark; plaintext PIN is automatically expunged from memory and view.

