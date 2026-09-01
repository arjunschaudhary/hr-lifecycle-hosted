begin;

revoke execute on function
public.debug_signed_offer_resubmit_eligibility()
from public;

revoke execute on function
public.debug_signed_offer_resubmit_eligibility()
from anon;

revoke execute on function
public.debug_signed_offer_resubmit_eligibility()
from authenticated;

revoke execute on function
public.debug_signed_offer_resubmit_eligibility()
from service_role;

drop function if exists
public.debug_signed_offer_resubmit_eligibility();

commit;
