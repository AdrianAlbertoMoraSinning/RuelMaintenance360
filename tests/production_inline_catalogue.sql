begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','ea8946ea-e093-4ad1-a886-954fb91187db',true);
do $$
declare u uuid:='772039c9-622b-430c-90d7-8278adaa42aa';p uuid;o uuid;c uuid;s uuid;request uuid:=gen_random_uuid();data jsonb;failed boolean;before_c integer;before_s integer;result jsonb;
begin
 p:=(public.production_command('product',jsonb_build_object('business_unit_id',u,'name','QA inline product','unit','m³','kind','product'))->>'id')::uuid;
 data:=jsonb_build_object('business_unit_id',u,'request_id',request,'product_id',p,'quantity',24,'due_at',now()+interval '1 day','new_customer',jsonb_build_object('name','QA  Voice Customer','email','qa@example.invalid','phone',''),'new_site',jsonb_build_object('name','QA Site A','address','QA Site Address'),'instructions','Dictated order instructions');
 o:=(public.production_command('order',data)->>'id')::uuid;
 select customer_id,site_id into c,s from public.production_orders where id=o;
 if not exists(select 1 from public.production_customers where id=c and name='QA Voice Customer') or not exists(select 1 from public.production_sites where id=s and customer_id=c) then raise exception 'New customer/site not saved in catalogue';end if;
 if (public.production_command('order',data)->>'id')::uuid<>o or(select count(*) from public.production_customers where id=c)<>1 then raise exception 'Retry duplicated inline catalogue';end if;
 failed:=false;begin perform public.production_command('order',data||jsonb_build_object('quantity',25));exception when raise_exception then failed:=true;end;if not failed then raise exception 'Changed retry accepted';end if;
 failed:=false;begin perform public.production_command('order',data||jsonb_build_object('request_id',gen_random_uuid(),'new_customer',jsonb_build_object('name','  qa voice   customer ')));exception when raise_exception then failed:=true;end;if not failed then raise exception 'Duplicate customer accepted';end if;
 -- Create a different site for the same customer without leaving the order.
 result:=public.production_command('order',data||jsonb_build_object('request_id',gen_random_uuid(),'new_customer',null,'customer_id',c,'new_site',jsonb_build_object('name','QA Site B','address','QA Other Address')));
 if not exists(select 1 from public.production_orders where id=(result->>'id')::uuid and customer_id=c and site_id<>s) then raise exception 'Existing customer/new site failed';end if;
 select count(*) into before_c from public.production_customers;select count(*) into before_s from public.production_sites;
 failed:=false;begin perform public.production_command('order',data||jsonb_build_object('request_id',gen_random_uuid(),'new_customer',jsonb_build_object('name','QA Must Roll Back'),'quantity',0));exception when check_violation then failed:=true;end;if not failed then raise exception 'Invalid quantity accepted';end if;
 if(select count(*) from public.production_customers)<>before_c or(select count(*) from public.production_sites)<>before_s then raise exception 'Failed order left orphan customer/site';end if;
 failed:=false;begin perform public.production_command('order',data||jsonb_build_object('request_id',gen_random_uuid(),'product_id',null,'new_customer',jsonb_build_object('name','QA Missing Product')));exception when raise_exception then failed:=true;end;if not failed then raise exception 'Non-catalogue product accepted';end if;
 if(select count(*) from public.production_customers)<>before_c then raise exception 'Missing product left catalogue records';end if;
 perform set_config('request.jwt.claim.sub','0d87a0bf-b3a8-434b-9012-45c5d9bacfff',true);
 failed:=false;begin perform public.production_command('order',data||jsonb_build_object('request_id',gen_random_uuid(),'new_customer',jsonb_build_object('name','QA Unauthorized')));exception when raise_exception then failed:=true;end;if not failed then raise exception 'Supervisor created an order/customer';end if;
end $$;
reset role;
select 'production_inline_catalogue_passed' as result;
rollback;
