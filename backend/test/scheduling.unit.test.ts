import {test} from 'node:test';
import assert from 'node:assert/strict';
const {schedulePlan,scheduleRequest,scheduleIndicator,scheduleSettings}=require('../dist/src/modules/scheduling/schedule.policy');
const r={schedulePrepMinutes:20,estimatedDeliveryMaxMinutes:45,scheduleOpenMinute:540,scheduleCloseMinute:1380,scheduleWeekdays:[0,1,2,3,4,5,6],operatingStatus:'OPEN',deliveryAvailability:true};
test('IST hours, UTC plans, lead time and closed/invalid slots',()=>{
 process.env.NODE_ENV='test';const now=new Date('2026-11-15T03:00:00Z');
 const p=schedulePlan(r,new Date('2026-11-15T14:30:00Z'),now);
 assert.equal(p.deliveryWindowStart.toISOString(),'2026-11-15T14:25:00.000Z');assert.equal(p.deliveryWindowEnd.toISOString(),'2026-11-15T14:35:00.000Z');
 for(const date of ['invalid','2026-11-14T14:30:00Z','2026-11-15T14:31:00Z','2026-11-15T03:45:00Z','2026-11-15T18:00:00Z','2026-11-25T14:30:00Z'])assert.throws(()=>schedulePlan(r,new Date(date),now));
 assert.throws(()=>schedulePlan({...r,scheduleWeekdays:[]},new Date('2026-11-15T14:30:00Z'),now));
 assert.throws(()=>schedulePlan({...r,operatingStatus:'CLOSED'},new Date('2026-11-15T14:30:00Z'),now));
});
test('schedule request shape and production cannot enable accelerated demo',()=>{
 assert.deepEqual(scheduleRequest({}),{});assert.deepEqual(scheduleRequest({deliveryMode:'NOW'}),{});
 for(const input of [{deliveryMode:'SCHEDULED'},{scheduledDeliveryAt:'2026-11-15T14:30:00Z'},{deliveryMode:'SCHEDULED',scheduledDeliveryAt:'2026-11-15T20:00:00+05:30'}])assert.throws(()=>scheduleRequest(input));
 process.env.SCHEDULE_DEMO_FAST='true';for(const env of ['production','test']){process.env.NODE_ENV=env;assert.equal(scheduleSettings().fast,false);}
 process.env.NODE_ENV='development';assert.equal(scheduleSettings().fast,true);
 const fast=schedulePlan(r,new Date('2026-11-15T06:33:00Z'),new Date('2026-11-15T06:30:00Z'));assert.equal(scheduleIndicator({...fast,status:'PENDING_RESTAURANT'},new Date('2026-11-15T06:30:00Z')),'SCHEDULED');
 // Accelerated plan is shorter than the ±5-min window: preparing on time must not read At risk, and the rider gets pickup slack.
 assert.equal(fast.dispatchReleaseAt.getTime(),fast.preparationStartAt.getTime());
 assert.equal(scheduleIndicator({...fast,status:'PREPARING'},new Date(fast.preparationStartAt.getTime()+10000)),'PREPARING');
 assert.equal(scheduleIndicator({...fast,status:'READY_FOR_PICKUP'},new Date(fast.expectedPickupAt.getTime()-5000)),'ON_TRACK');
 assert.equal(scheduleIndicator({...fast,status:'READY_FOR_PICKUP'},new Date(fast.expectedPickupAt.getTime()+1000)),'AT_RISK');
 assert.equal(scheduleIndicator({...fast,status:'OUT_FOR_DELIVERY'},new Date(fast.expectedPickupAt.getTime()+1000)),'ON_TRACK');delete process.env.SCHEDULE_DEMO_FAST;process.env.NODE_ENV='test';
});
test('recorded delivery and milestone delays determine truthful schedule indicators',()=>{
 const o={...schedulePlan(r,new Date('2026-11-15T14:30:00Z'),new Date('2026-11-15T03:00:00Z')),status:'ACCEPTED'};
 assert.equal(scheduleIndicator(o,new Date('2026-11-15T04:00:00Z')),'SCHEDULED');
 assert.equal(scheduleIndicator(o,o.preparationStartAt),'AT_RISK');
 assert.equal(scheduleIndicator({...o,status:'PREPARING'},o.preparationStartAt),'PREPARING');
 assert.equal(scheduleIndicator({...o,status:'OUT_FOR_DELIVERY'},o.expectedPickupAt),'ON_TRACK');
 assert.equal(scheduleIndicator(o,new Date('2026-11-15T14:36:00Z')),'DELAYED');
 assert.equal(scheduleIndicator({...o,status:'DELIVERED',actualDeliveryAt:o.deliveryWindowStart}),'DELIVERED_WITHIN_WINDOW');
 assert.equal(scheduleIndicator({...o,status:'DELIVERED',actualDeliveryAt:new Date('2026-11-15T14:40:00Z')}),'DELIVERED_OUTSIDE_WINDOW');
});
