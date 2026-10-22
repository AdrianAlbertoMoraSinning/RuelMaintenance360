-- Tracking is served by the Edge Function, never by anonymous database RPC.
revoke execute on function public.production_tracking(text) from public,anon,authenticated;
grant execute on function public.production_tracking(text) to service_role;
create policy production_tracking_service on private.production_tracking for all to service_role using(true) with check(true);
