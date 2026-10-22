# Observation recipients and CEO escalation

The default remains the reporter's direct manager (or the existing unit-supervisor fallback). Supervisors and managers may address a new observation to the configured active CEO. Their assigned manager remains copied and retains technical review and AI acceptance accountability. Operators keep supervisor routing; choosing arbitrary users or bypassing their supervisor is rejected by the server.

Field Observations → Report observation → **Send to** defaults to the manager's name. Selecting **Guy Munden — CEO** shows **CC: [direct manager]**. The chosen recipient is persisted with offline drafts; queued reports do not silently lose their destination. Existing reports can use **Send to Guy Munden · keep manager copied** from the detail screen, by the reporting supervisor/manager or assigned manager.

Routing preserves the observation ID, attachments, workflow status, Safety Case, assigned manager and history. It adds an addressed recipient and an audit event. In-app notifications go to the CEO and manager; Safety retains its OHS recipients and severity. No automatic email or SMS is sent by this change.

Only the reporter, assigned manager and addressed recipient can send messages. Other authorized readers remain observers. Each message notifies the other participants; read state is per recipient. Existing bilateral observations remain bilateral until explicitly addressed. The AI gate is still acceptance by the assigned manager; forwarding alone does not approve an observation for AI.

Validation: `tests/observation_ceo_routing.sql` rolls back its fixtures, testing default routing, explicit CEO selection, idempotent retries, three-party chat, manager forwarding, denied operator/outsider bypass, direct-write denial, AI review and Safety retention. Existing conversation, evidence, AI and Safety regression suites remain required.
