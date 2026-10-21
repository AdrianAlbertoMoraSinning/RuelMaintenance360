import test from 'node:test'
import assert from 'node:assert/strict'
import {performanceNavigation,scopeUnitQuery,unitContext} from '../src/lib/unitScope.ts'
test('every unit module inherits the selected performance unit, including direct observation/task records',()=>{
 for(const destination of ['assets','work_orders','inspections','reports','observations','todo'])assert.equal(performanceNavigation('business_units',destination,undefined,'plant',null),'plant')
 assert.equal(performanceNavigation('business_units','observations','obs-1','plant',null),'plant')
 assert.equal(performanceNavigation('business_units','todo','task-1','plant',null),'plant')
})
test('field tabs keep their origin while returning to performance, menu navigation and external notifications clear unit focus',()=>{
 assert.equal(performanceNavigation('observations','todo',undefined,undefined,'plant'),'plant')
 for(const destination of ['business_units','assets','work_orders','inspections','reports','dashboard'])assert.equal(performanceNavigation('todo',destination,undefined,undefined,'plant'),null)
 assert.equal(performanceNavigation('todo','observations','other-unit-observation',undefined,'plant'),null)
})
test('focused queries and selectors exclude other units without changing the normal corporate scope',()=>{
 const query={calls:[],eq(column,value){this.calls.push([column,value]);return this}}
 assert.equal(scopeUnitQuery(query,'plant'),query);assert.deepEqual(query.calls,[['business_unit_id','plant']]);scopeUnitQuery(query,null);assert.equal(query.calls.length,1)
 const units=[{id:'plant',name:'Concrete'},{id:'shop',name:'Shop'}];assert.deepEqual(unitContext(units,'plant'),[units[0]]);assert.deepEqual(unitContext(units,'missing'),[]);assert.equal(unitContext(units,null),units)
})
