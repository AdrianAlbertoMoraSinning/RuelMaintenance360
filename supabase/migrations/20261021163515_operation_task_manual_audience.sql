update public.section_manuals set audience=enum_range(null::public.app_role),updated_at=now() where section_key='todo';
