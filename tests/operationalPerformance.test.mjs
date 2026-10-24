import test from 'node:test'
import assert from 'node:assert/strict'
import {isTrainingPerformanceRecord,operationalPerformanceRecords} from '../src/lib/operationalPerformance.ts'
test('merged fleet training costs do not enter operational costs, downtime, assets or PM indicators',()=>{
 const assets=[{id:'real',asset_code:'TRK-131'},{id:'mixer',asset_code:'MOC-MOB-001'},{id:'pump',asset_code:'MOC-MOB-003'}];
 const orders=[{asset_id:'mixer',title:'[MOC] Mixer 101 chassis service',cost:1035,downtime:4.5},{asset_id:'pump',title:'[MOC] Pump 32 m outrigger proximity switch',cost:2650,downtime:1.4}];
 const live=operationalPerformanceRecords(assets,orders,[{asset_id:'mixer',title:'Weekly service'}],[{asset_id:'pump',observations:'Training check'}]);
 assert.deepEqual(live.assets,[assets[0]]);assert.equal(live.orders.reduce((n,w)=>n+w.cost,0),0);assert.deepEqual(live.plans,[]);assert.deepEqual(live.inspections,[]);assert.equal(orders.reduce((n,w)=>n+w.cost,0),3685);
});
test('real costs remain and a marked MOC record on a real asset is excluded independently',()=>{
 const assets=[{id:'real',asset_code:'TRK-131'}],real={asset_id:'real',title:'Actual service',cost:250};
 const live=operationalPerformanceRecords(assets,[real,{asset_id:'real',title:'[MOC TRAINING] demonstration',cost:999}],[],[{asset_id:'real',observations:'Actual inspection'},{asset_id:'real',observations:'[MOC] simulated inspection'}]);
 assert.deepEqual(live.orders,[real]);assert.equal(live.inspections.length,1);assert.equal(isTrainingPerformanceRecord({title:'Replace MOC valve'}),false);
});
