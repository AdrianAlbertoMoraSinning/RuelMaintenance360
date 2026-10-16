# RUEL Maintenance 360 — Device Connector Agent

This folder defines the transport-neutral core for the future mobile/desktop connector that bridges physical diagnostic interfaces into RUEL Maintenance 360.

## Purpose

The Device Connector Agent does **not** replace OEM diagnostic software. It performs four controlled functions:

1. identify the local connector/gateway and collect machine identity (serial/VIN/J1939 NAME/ECU/PLC station/OEM ID);
2. normalize readings and fault events from an approved adapter or OEM export;
3. queue payloads locally when the device is offline and sync them later;
4. upload only after the server resolves or a user confirms the target asset.

## Supported transport families

- CAN / SAE J1939
- OBD-II
- PLC / Modbus TCP or serial
- OEM CSV/JSON/XML exports
- USB / serial adapters
- Bluetooth/Wi-Fi adapters through a native wrapper
- Telematics REST APIs

The web application is the commissioning/control plane. Actual USB, Bluetooth, CAN or serial access must be implemented in a compatible native/desktop runtime and tested with the specific adapter. iOS/Android/browser transport support differs by platform.

## Normalized payload

The transport adapter should produce a `NormalizedDiagnosticBatch` and submit it through the authenticated Maintenance 360 client. The server then performs:

`Agent -> Session -> Machine identity match -> Gateway mapping -> Condition reading / Fault event -> Alert -> Predictive Work Order -> Normal approval chain`.

Never hard-code OEM thresholds or fault definitions in the connector. Those belong to controlled OEM profiles / fault-code library records in Maintenance 360.

## Offline queue

The native wrapper should persist encrypted batches locally with these states:

- `captured`
- `identity_pending`
- `ready_to_sync`
- `syncing`
- `synced`
- `failed`

A failed upload must be retryable and idempotent. Raw adapter data should be retained only as long as required by RUEL policy.

## Production commissioning sequence

1. register Device Agent in Maintenance 360;
2. approve the agent and assign a responsible person;
3. connect the approved physical adapter;
4. scan machine identity;
5. resolve/confirm the asset match;
6. select the controlled OEM diagnostic profile;
7. verify signal mappings against OEM/engineering documentation;
8. perform a supervised test upload;
9. validate generated Condition Readings/Fault Events;
10. only then enable routine field use.
