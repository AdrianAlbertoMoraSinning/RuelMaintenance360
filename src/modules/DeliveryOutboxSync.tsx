import {useEffect} from 'react'
import {syncDeliveryOutbox} from '../lib/productionClient'
export default function DeliveryOutboxSync({userId}:{userId:string}){useEffect(()=>{const sync=()=>void syncDeliveryOutbox(userId).catch(()=>{/* Durable queue is retained; delivery screen shows the error on retry. */});sync();window.addEventListener('online',sync);return()=>window.removeEventListener('online',sync)},[userId]);return null}
