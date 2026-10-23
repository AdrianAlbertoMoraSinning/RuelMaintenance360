-- Commit enum values before they are used in policies, triggers or functions.
alter type public.app_role add value if not exists 'driver';
alter type public.personnel_category add value if not exists 'driver';
