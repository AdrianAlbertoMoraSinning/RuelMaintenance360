# Operational To-do — 21 October 2026

The active Shareholders form the task committee (currently Marcel Ruel and Sylvain Ruel). They assign only to the designated CEO (currently Guy Munden). The CEO assigns managers or supervisors; managers assign their directly reporting supervisors; supervisors assign their directly reporting operators/technicians. Application administration alone does not bypass delegation.

Every role has Observations and My To-do. The operator keeps the same report capture screen, with a second large To-do button. Leaders have their received assignments above and their delegated assignments below. Views include today/overdue, upcoming, all pending, and completed/cancelled history. Scheduling uses America/Edmonton, regardless of the viewer's browser timezone.

Assignments support priority, emergency/manual/maintenance origins, optional business unit and machine, due date/time, instructions, required checklist, progress and a written activity history. Browser voice input transcribes progress notes; the user reviews the text before sending. Voice availability depends on the phone/browser; keyboard dictation remains a fallback. The application does not store a task audio recording.

Delegating from an existing assignment creates a linked child. Existing delegated assignments can also be attached to an open task received by the assigner. A link cannot be silently detached/reparented. Child events are copied to every linked ancestor, with the source task and actor preserved. Parent progress is not automatically fabricated from child percentages. A parent cannot request completion with open children.

The assignee requests completion after finishing all required steps. The original assigner approves completion or returns it with a note. Approval archives the task without deleting its history. New activity has a per-person read cursor; opening an older snapshot cannot clear a newer update. Optimistic concurrency rejects stale progress/review writes.

Scheduled WOs and due PM plans (seven-day date horizon, or meter threshold reached) are materialized idempotently for the current user and authorized direct assignees when My To-do refreshes. A WO absorbs an existing open PM reminder for the same plan/assignee. PM reminders remain distinct across controlled maintenance cycles. Source cancellation/reassignment retires the old reminder, or blocks it if it still has open children. Missing reporting authority/unit access prevents generation instead of bypassing governance.

To-do does not approve execution, spending, purchases, or controlled WO completion. A task linked to a WO cannot request completion until that WO has completed its existing workflow. Plan advancement continues through the controlled maintenance process. To-do activity is not added to AI observation memory; supervisor acceptance of observations remains required.

Task notifications are in-app, with refresh every 30 seconds while the page is visible and on focus. No SMS or new task emails are sent. Task updates require a connection; failure preserves the unsent note in the open form and reports the error. Operator observation offline capture remains available separately.

Calendar & Backlog shows authorized pending tasks beside PM/WO entries and opens the task. Administration shows the committee and designated CEO. Active Shareholder membership follows personnel category and account activation changes.

Validation: `npm run test:tasks`, `npm run test:operator`, `npm run test:auth`, `npm run test:ai`, and `npm run build`. Database integration tests `tests/operation_tasks.sql` and `tests/operation_task_sources.sql` execute within BEGIN/ROLLBACK against the real configured hierarchy; they preserve zero production fixtures. They cover delegation restrictions, RLS, deep event propagation, read cursors, stale-write rejection, required checklists/review, source idempotency, meter deadlines, PM-to-WO absorption, and the controlled approval boundary. Phone interaction still needs an authenticated on-device acceptance check.


## Task conversation

Each task includes a bilateral conversation between its assigner and assignee, available at every organizational level. Existing direct task comments appear in the same transcript. Messages show their author, assignment side and full timestamp in Alberta time; both people can continue clarifying completed/cancelled tasks without changing their archived state. Authorized owners of linked leadership tasks can read the evidence, but only the two direct participants can reply.

The transcript refreshes every four seconds while its task screen is active and the browser tab is visible, and immediately on focus. Older messages load in pages without losing the newer conversation. Switching the operator back to Observations suspends chat polling/read acknowledgement. Reading chat has its own cursor and cannot clear unread progress/review events. Chat-only events do not invalidate an unsent progress/review draft; other events still reject stale state changes.

Messages are immutable through authenticated application access: no edit/delete controls or write grants. A client UUID makes delivery retries idempotent, including notifications. Failed/uncertain delivery retains the text and retry key in a user-and-task-scoped session draft; the app confirms sending only after the server accepts it. These temporary drafts are not server evidence until sent. Chat requires a connection and never sends a queued message automatically. Message bodies are escaped as literal text.

Validation adds `tests/taskConversation.test.mjs` to `npm run test:tasks` and `tests/operation_task_conversation.sql` for all four delegation levels, two-way authorship, cross-task privacy, immutable evidence permissions, duplicate retries, unread chat/progress separation, chat-safe optimistic concurrency and archived-task retention. All database fixtures roll back.
