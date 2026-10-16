import { readFileSync, existsSync } from 'node:fs'

const requiredFiles = [
  'src/modules/BusinessUnitsPerformance.tsx',
  'src/modules/MaintenancePlanningSection.tsx',
  'src/modules/PMCompliancePanel.tsx',
  'src/modules/MaintenancePlansSection.tsx',
  'src/modules/PMAutomationPanel.tsx',
  'src/modules/MeterReadingsPanel.tsx',
  'src/modules/ConditionMonitoringPanel.tsx',
  'src/modules/EquipmentDiagnosticsSection.tsx',
  'src/modules/EquipmentDiagnosticsEmbedded.tsx',
  'src/modules/DeviceConnectorAgentPanel.tsx',
  'src/modules/SystemReadinessAuditSection.tsx',
  'src/modules/ApprovalsDashboard.tsx',
  'src/modules/ApprovalsDashboardLive.tsx',
  'src/modules/WorkOrdersSection.tsx',
  'src/modules/WorkOrderResources.tsx',
  'src/modules/InventorySection.tsx',
  'src/modules/InspectionsSection.tsx',
  'src/modules/DocumentsSection.tsx',
  'src/modules/TechnicalAssistantSection.tsx',
  'src/modules/ReportsSection.tsx',
  'src/modules/AdminSection.tsx',
  'device-agent/README.md',
  'device-agent/src/normalizer.ts',
  'public/favicon.svg',
  'public/favicon-32x32.svg',
  'public/favicon-16x16.svg',
  'public/apple-touch-icon.png',
  'public/android-chrome-192x192.png',
  'public/android-chrome-512x512.png',
  'public/mstile-150x150.png',
  'public/safari-pinned-tab.svg',
  'public/site.webmanifest'
]

const requiredMarkers = {
  'src/App.tsx': ['BusinessUnitsPerformance','MaintenancePlanningSection','ApprovalsDashboard','TechnicalAssistantSection','SystemReadinessAuditSection','Business Unit Performance','Calendar & Backlog','My Approvals','System Readiness Audit'],
  'src/modules/BusinessUnitsPerformance.tsx': ['Operational Performance by Unit','Work order status','Backlog aging','Downtime trend','Maintenance cost breakdown','Inspection results'],
  'src/modules/MaintenancePlanningSection.tsx': ['PMCompliancePanel','technician_capacity','planned_labour_hours','Planned vs unplanned','Current Week Technician Capacity','Capacity Outlook'],
  'src/modules/PMCompliancePanel.tsx': ['pm_work_order_performance','pm_forecast','Compliance & 90-Day Forecast','PM compliance','Overdue PM WOs'],
  'src/modules/MaintenancePlansSection.tsx': ['PMAutomationPanel','MeterReadingsPanel','ConditionMonitoringPanel','EquipmentDiagnosticsEmbedded','Controlled interval requirement'],
  'src/modules/PMAutomationPanel.tsx': ['generate_due_maintenance_work_orders','maintenance_due_board','maintenance_plan_parts','pm_automation_runs','Daily scheduled scan active','Run PM automation','Required parts'],
  'src/modules/MeterReadingsPanel.tsx': ['meter_readings','hour_meter','odometer_km','Record meter'],
  'src/modules/ConditionMonitoringPanel.tsx': ['asset_condition_rules','asset_condition_readings','asset_condition_alerts','create_condition_work_order','Condition Monitoring & Predictive Alerts','Record & evaluate'],
  'src/modules/EquipmentDiagnosticsSection.tsx': ['diagnostic_gateways','diagnostic_fault_events','diagnostic_ingestion_log','ingest_diagnostic_payload','create_diagnostic_fault_work_order','Equipment Diagnostics Gateway','CAN / J1939','PLC / Modbus','Telematics API'],
  'src/modules/EquipmentDiagnosticsEmbedded.tsx': ['EquipmentDiagnosticsSection','DeviceConnectorAgentPanel'],
  'src/modules/DeviceConnectorAgentPanel.tsx': ['diagnostic_device_agents','diagnostic_oem_profiles','diagnostic_fault_code_library','diagnostic_asset_identities','diagnostic_device_sessions','register_device_session','confirm_device_session_asset','Device Connector / Mobile Diagnostic Agent','Automatic machine matching','OEM Profiles & Fault Library'],
  'src/modules/SystemReadinessAuditSection.tsx': ['system_readiness_audit','End-to-End Audit','Critical findings','Run audit'],
  'device-agent/README.md': ['Device Connector Agent','Machine identity','Offline queue','CAN / SAE J1939','PLC / Modbus'],
  'device-agent/src/normalizer.ts': ['NormalizedDiagnosticBatch','MachineIdentity','DiagnosticTransportAdapter','OfflineDiagnosticQueue','normalizeJsonPayload'],
  'src/modules/ApprovalsDashboardLive.tsx': ['Approval aging','No automatic SLA classification','Informational aging only'],
  'src/modules/WorkOrdersSection.tsx': ['execution_approval_status','approve_work_order_execution_manager','approve_work_order_execution_super_admin','WorkOrderEvidence','WorkOrderResources','Create work order & plan parts','additional parts can also be added later'],
  'src/modules/WorkOrderResources.tsx': ['add_work_order_part_requirement','issue_part_to_work_order','return_part_from_work_order','Dynamic material planning','quantity_available','quantity_on_order'],
  'src/modules/InventorySection.tsx': ['inventory_stock_summary','inventory_kardex','inventory_counts','transfer_inventory_part','inventory_purchase_orders','inventory_purchase_order_lines','receive_purchase_order_line','inventory_replenishment_report','inventory_responsibility_history','Parts, Warehouses & Kardex','Purchase Orders & Receipts','Physical Counts','Warehouses & Storage Positions','Custody History'],
  'src/modules/InspectionsSection.tsx': ['OFFLINE_KEY','LEGACY_OFFLINE_KEY','submit_inspection','serverInspectionId','Sync now','Saved field photos','idempotent offline synchronization'],
  'src/modules/AdminSection.tsx': ['corporate_manager_id','maintenance_approval_settings','InspectionTemplateAdmin','Corporate Cost Authorization Threshold'],
  'src/modules/DocumentsSection.tsx': ['tesseract.js','document_chunks','OCR'],
  'index.html': ['/favicon.svg','/apple-touch-icon.png','/mstile-150x150.png','/safari-pinned-tab.svg','/site.webmanifest'],
  'public/site.webmanifest': ['/android-chrome-192x192.png','/android-chrome-512x512.png']
}

const errors = []
for (const file of requiredFiles) if (!existsSync(file)) errors.push(`Missing critical module: ${file}`)
for (const [file, markers] of Object.entries(requiredMarkers)) {
  if (!existsSync(file)) { errors.push(`Missing baseline file: ${file}`); continue }
  const text = readFileSync(file, 'utf8')
  for (const marker of markers) if (!text.includes(marker)) errors.push(`Regression marker missing in ${file}: ${marker}`)
}
if (errors.length) {
  console.error('\nRUEL Maintenance 360 regression guard FAILED:\n')
  for (const error of errors) console.error(`- ${error}`)
  console.error('\nA previously approved capability appears to have been removed or reverted. Restore it before merging/deploying.\n')
  process.exit(1)
}
console.log('RUEL Maintenance 360 regression guard passed: critical approved capabilities are present.')
