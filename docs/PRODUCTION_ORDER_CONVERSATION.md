# Order conversation · 0.3.6

Open Production & Dispatch → Customer orders → Open order & deliveries. The Order conversation is immediately available, even if no driver or load has been assigned. Write a question, instruction or reply, or tap the microphone next to Send message to dictate editable text. Review and send. Every message retains its author's name and captured/received time.

All active staff with existing authorized access to that order can read and participate, including its assigned active drivers. No new unit or corporate permissions are granted. Drivers open Add update on their current delivery to access both Order conversation and the existing load-specific delivery updates. Load photos, videos, recorded audio and customer sharing retain their previous controls.

Messages are attached to the permanent order ID. Replacing TEMP-22 with the Aimsio reference preserves the thread. Completion or cancellation retains the evidence and authorized participants can continue clarifying it. Messages do not change production quantity, readiness, departure, completion, inventory or customer acceptance. Internal discussion is not automatically included in the customer's tracking link.

The latest 50 messages load first, older history is available through Load earlier messages, and new messages refresh every 15 seconds while the screen is visible. While reading earlier pages, automatic refresh pauses to keep the history in place; Return to latest messages resumes it. Sending writes to the existing account-bound IndexedDB outbox first; drafts clear only after durable local storage succeeds. If offline, the interface explicitly says the message has not been sent. The existing sync mechanism retries upon reconnect. Identical request IDs do not duplicate messages; altered payloads and forged actors are rejected.

Notifications go to the creator, previous order-chat participants, assigned drivers and the plant unit's operating managers, excluding the sender. Recipient selection also checks active status and current access so removed participants do not receive new message snippets. Existing in-app alerts and entry bubbles handle these notifications.

Backend APIs are public invokers to guarded private implementations, explicitly granted to authenticated only. Reads enforce the same order audience, cursor scope and pagination. The write API checks the signed-in actor, order access, content length and device clock. Existing activity-table SELECT-only grants/RLS preserve immutable client evidence. No chat-related schema tables or anonymous APIs were added.

Validation: component and queue-routing tests, actual database rollback workflow covering pre-assignment chat, multiple authors, assigned driver participation, denied outsiders, retries, notifications, reference changes, private customer tracking, pagination, completion and immutable evidence. Security advisors show no additional findings. Physical phone testing remains a pilot check.
