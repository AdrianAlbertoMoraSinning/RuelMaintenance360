import { readFileSync, existsSync } from 'node:fs'

const requiredFiles = [
  'src/modules/BusinessUnitsPerformance.tsx',
  'src/modules/MaintenancePlanningSection.tsx',
  'src/modules/ApprovalsDashboard.tsx',
  'src/modules/ApprovalsDashboardLive.tsx',
  'src/modules/WorkOrdersSection.tsx',
  'src/modules/InspectionsSection.tsx',
  'src/modules/DocumentsSection.tsx',
  'src/modules/TechnicalAssistantSection.tsx',
  'src/modules/ReportsSection.tsx',
  'src/modules/AdminSection.tsx'
]

const requiredMarkers = {
  'src/App.tsx': [
    "BusinessUnitsPerformance",
    "MaintenancePlanningSection",
    "ApprovalsDashboard",
    "TechnicalAssistantSection",
    "Business Unit Performance",
    "Calendar & Backlog",
    "My Approvals"
  ],
  'src/modules/BusinessUnitsPerformance.tsx': [
    'Operational Performance by Unit',
    'Work order status',
    'Backlog aging',
    'Downtime trend',
    'Maintenance cost breakdown',
    'Inspection results'
  ],
  'src/modules/MaintenancePlanningSection.tsx': [
    'technician_capacity',
    'planned_labour_hours',
    'Planned vs unplanned',
    'Current Week Technician Capacity',
    'Capacity Outlook'
  ],
  'src/modules/WorkOrdersSection.tsx': [
    'execution_approval_status',
    'approve_work_order_execution_manager',
    'approve_work_order_execution_super_admin',
    'WorkOrderEvidence',
    'WorkOrderResources'
  ],
  'src/modules/InspectionsSection.tsx': [
    'OFFLINE_KEY',
    'offline',
    'Sync now'
  ],
  'src/modules/AdminSection.tsx': [
    'corporate_manager_id',
    'maintenance_approval_settings',
    'InspectionTemplateAdmin',
    'Corporate Cost Authorization Threshold'
  ],
  'src/modules/DocumentsSection.tsx': [
    'tesseract.js',
    'document_chunks',
    'OCR'
  ]
}

const errors = []
for (const file of requiredFiles) {
  if (!existsSync(file)) errors.push(`Missing critical module: ${file}`)
}

for (const [file, markers] of Object.entries(requiredMarkers)) {
  if (!existsSync(file)) {
    errors.push(`Missing baseline file: ${file}`)
    continue
  }
  const text = readFileSync(file, 'utf8')
  for (const marker of markers) {
    if (!text.includes(marker)) errors.push(`Regression marker missing in ${file}: ${marker}`)
  }
}

if (errors.length) {
  console.error('\nRUEL Maintenance 360 regression guard FAILED:\n')
  for (const error of errors) console.error(`- ${error}`)
  console.error('\nA previously approved capability appears to have been removed or reverted. Restore it before merging/deploying.\n')
  process.exit(1)
}

console.log('RUEL Maintenance 360 regression guard passed: critical approved capabilities are present.')
