import { FormEvent, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'

export type BusinessUnit = {
  id: string
  code: string
  name: string
  unit_type: string
  brand_label: string
  address: string | null
}

type Asset = {
  id: string
  business_unit_id: string
  asset_code: string
  name: string
  asset_category: string
  manufacturer: string | null
  model: string | null
  serial_number: string | null
  year: number | null
  status: string
  criticality: number
  odometer_km: number | null
  hour_meter: number | null
  notes: string | null
}

type Props = {
  units: BusinessUnit[]
  userId: string
  role: string
}

const blank = {
  business_unit_id: '', asset_code: '', name: '', asset_category: '', manufacturer: '', model: '', serial_number: '', year: '', criticality: '3', notes: ''
}

export default function AssetsSection({ units, userId, role }: Props) {
  const [assets, setAssets] = useState<Asset[]>([])
  const [loading, setLoading] = useState(true)
  const [query, setQuery] = useState('')
  const [unitFilter, setUnitFilter] = useState('all')
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState(blank)
  const [saving, setSaving] = useState(false)
  const [message, setMessage] = useState('')
  const [meterAsset, setMeterAsset] = useState<Asset | null>(null)
  const [meterType, setMeterType] = useState<'odometer_km' | 'hour_meter'>('hour_meter')
  const [meterValue, setMeterValue] = useState('')

  const canCreate = ['super_admin','corporate_manager','unit_supervisor','technician'].includes(role)

  async function loadAssets() {
    setLoading(true)
    const { data, error } = await supabase
      .from('assets')
      .select('id,business_unit_id,asset_code,name,asset_category,manufacturer,model,serial_number,year,status,criticality,odometer_km,hour_meter,notes')
      .order('asset_code')
    if (!error && data) setAssets(data as Asset[])
    setLoading(false)
  }

  useEffect(() => { loadAssets() }, [])

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase()
    return assets.filter((a) => {
      const matchesUnit = unitFilter === 'all' || a.business_unit_id === unitFilter
      const haystack = `${a.asset_code} ${a.name} ${a.asset_category} ${a.manufacturer || ''} ${a.model || ''} ${a.serial_number || ''}`.toLowerCase()
      return matchesUnit && (!q || haystack.includes(q))
    })
  }, [assets, query, unitFilter])

  async function createAsset(e: FormEvent) {
    e.preventDefault()
    setSaving(true); setMessage('')
    const payload = {
      business_unit_id: form.business_unit_id,
      asset_code: form.asset_code.trim().toUpperCase(),
      name: form.name.trim(),
      asset_category: form.asset_category.trim(),
      manufacturer: form.manufacturer.trim() || null,
      model: form.model.trim() || null,
      serial_number: form.serial_number.trim() || null,
      year: form.year ? Number(form.year) : null,
      criticality: Number(form.criticality),
      notes: form.notes.trim() || null,
    }
    const { error } = await supabase.from('assets').insert(payload)
    if (error) setMessage(error.message)
    else {
      setMessage('Asset created successfully.')
      setForm(blank)
      setShowForm(false)
      await loadAssets()
    }
    setSaving(false)
  }

  async function saveMeter(e: FormEvent) {
    e.preventDefault()
    if (!meterAsset || !meterValue) return
    const value = Number(meterValue)
    const unit = meterType === 'odometer_km' ? 'km' : 'h'
    const { error } = await supabase.from('meter_readings').insert({ asset_id: meterAsset.id, meter_type: meterType, value, unit, recorded_by: userId })
    if (!error) {
      await supabase.from('assets').update(meterType === 'odometer_km' ? { odometer_km: value } : { hour_meter: value }).eq('id', meterAsset.id)
      setMeterAsset(null); setMeterValue(''); await loadAssets()
    } else setMessage(error.message)
  }

  function unitName(id: string) { return units.find((u) => u.id === id)?.name || 'Assigned unit' }

  return (
    <div>
      <div className="hero-row compact-hero">
        <div><span className="eyebrow">Master Asset Registry</span><h1>Assets</h1><p className="muted">One controlled record for every plant, truck, pump, machine and maintainable component.</p></div>
        {canCreate && <button className="primary-button action-button" onClick={() => setShowForm(!showForm)}>+ New asset</button>}
      </div>

      {message && <div className={message.includes('successfully') ? 'success-box' : 'error-box'}>{message}</div>}

      {showForm && <form className="data-form" onSubmit={createAsset}>
        <div className="form-title"><div><span className="eyebrow">Asset setup</span><h2>Create asset</h2></div><button type="button" className="icon-button" onClick={() => setShowForm(false)}>×</button></div>
        <div className="form-grid">
          <label>Business unit<select required value={form.business_unit_id} onChange={e => setForm({...form,business_unit_id:e.target.value})}><option value="">Select unit</option>{units.map(u => <option key={u.id} value={u.id}>{u.name}</option>)}</select></label>
          <label>Asset code<input required value={form.asset_code} onChange={e => setForm({...form,asset_code:e.target.value})} placeholder="e.g. MIX-001" /></label>
          <label>Asset name<input required value={form.name} onChange={e => setForm({...form,name:e.target.value})} placeholder="Mixer Truck 1" /></label>
          <label>Category<input required value={form.asset_category} onChange={e => setForm({...form,asset_category:e.target.value})} placeholder="Mixer Truck / Pump / Crusher" /></label>
          <label>Manufacturer<input value={form.manufacturer} onChange={e => setForm({...form,manufacturer:e.target.value})} /></label>
          <label>Model<input value={form.model} onChange={e => setForm({...form,model:e.target.value})} /></label>
          <label>Serial / VIN<input value={form.serial_number} onChange={e => setForm({...form,serial_number:e.target.value})} /></label>
          <label>Year<input inputMode="numeric" value={form.year} onChange={e => setForm({...form,year:e.target.value})} /></label>
          <label>Criticality<select value={form.criticality} onChange={e => setForm({...form,criticality:e.target.value})}><option value="1">1 — Low</option><option value="2">2</option><option value="3">3 — Medium</option><option value="4">4</option><option value="5">5 — Critical</option></select></label>
          <label className="span-2">Notes<textarea value={form.notes} onChange={e => setForm({...form,notes:e.target.value})} rows={3} /></label>
        </div>
        <div className="form-actions"><button type="button" className="secondary-outline" onClick={() => setShowForm(false)}>Cancel</button><button className="primary-button action-button" disabled={saving}>{saving ? 'Saving…' : 'Create asset'}</button></div>
      </form>}

      <div className="toolbar">
        <input className="search-input" placeholder="Search asset, model, serial…" value={query} onChange={e => setQuery(e.target.value)} />
        <select value={unitFilter} onChange={e => setUnitFilter(e.target.value)}><option value="all">All business units</option>{units.map(u => <option key={u.id} value={u.id}>{u.name}</option>)}</select>
        <span className="count-chip">{visible.length} assets</span>
      </div>

      {loading ? <div className="loading-panel">Loading assets…</div> : visible.length === 0 ? <div className="empty-table">No assets recorded for the current filter.</div> :
      <div className="table-wrap"><table className="data-table"><thead><tr><th>Asset</th><th>Business unit</th><th>Equipment</th><th>Status</th><th>Criticality</th><th>Meters</th><th></th></tr></thead><tbody>{visible.map(a => <tr key={a.id}>
        <td><strong>{a.asset_code}</strong><small>{a.name}</small></td>
        <td>{unitName(a.business_unit_id)}</td>
        <td>{a.asset_category}<small>{[a.manufacturer,a.model].filter(Boolean).join(' · ') || 'Technical details pending'}</small></td>
        <td><span className={`status-pill ${a.status}`}>{a.status.replaceAll('_',' ')}</span></td>
        <td><span className={`criticality c${a.criticality}`}>C{a.criticality}</span></td>
        <td><span className="meter-line">{a.hour_meter != null ? `${a.hour_meter} h` : '— h'}</span><small>{a.odometer_km != null ? `${a.odometer_km} km` : '— km'}</small></td>
        <td><button className="secondary-outline mini" onClick={() => { setMeterAsset(a); setMeterType(a.asset_category.toLowerCase().includes('truck') ? 'odometer_km' : 'hour_meter') }}>Meter</button></td>
      </tr>)}</tbody></table></div>}

      {meterAsset && <div className="modal-backdrop" onClick={() => setMeterAsset(null)}><form className="modal-card" onSubmit={saveMeter} onClick={e => e.stopPropagation()}>
        <div className="form-title"><div><span className="eyebrow">Field reading</span><h2>{meterAsset.asset_code}</h2></div><button type="button" className="icon-button" onClick={() => setMeterAsset(null)}>×</button></div>
        <label>Meter type<select value={meterType} onChange={e => setMeterType(e.target.value as 'odometer_km'|'hour_meter')}><option value="hour_meter">Hour meter</option><option value="odometer_km">Odometer</option></select></label>
        <label>Current reading<input autoFocus required type="number" min="0" step="0.1" value={meterValue} onChange={e => setMeterValue(e.target.value)} /></label>
        <button className="primary-button action-button">Save reading</button>
      </form></div>}
    </div>
  )
}
