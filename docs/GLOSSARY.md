# UHC domain glossary

| Term | Meaning |
| --- | --- |
| Appointment | A patient's scheduled visit. Pending and confirmed appointments occupy their doctor's slot; cancelled, completed, and no-show appointments do not. |
| Check-in | A doctor-authorized pending-to-confirmed transition during the QR window. The current Appointment validation and owned slot-lock update commit in one transaction, so cancellation cannot be undone by a stale check-in. |
| Doctor day | One doctor's clinic calendar day in Baghdad time, UTC+3. Its appointment query and coordination record use that calendar date. |
| Doctor slot reservation | Transactional validation of the doctor's schedule, department, slot locks, and overlapping appointments, followed by the reservation writes. Moving an appointment releases only its own previous locks. |
| Doctor day availability | The scheduled slots and their current bookability for a doctor day. Availability is advisory; booking checks again inside its transaction. |
| Assistant offer | An expiring scheduling suggestion tied to a saved chat. Confirming it consumes the offer in the same transaction that creates the appointment and booking receipt. |
| Booking receipt | The saved appointment ID, booking reference, and QR code returned for an idempotent booking retry. The booking module checks this before validating an already-consumed offer. |
| Uncertain confirmation | A booking request whose result has not reached the client. The Assistant session retains the original offer and retry identity so its Booking receipt can be recovered even after a history refresh removes the consumed offer. A different offer cannot replace that confirmation while its outcome is unresolved. |
| Assistant turn | A patient message and its assistant outcome. A turn reservation owns its revision until completion or supersession; availability refresh stays read-only while the turn is unfinished. Generation and revision checks reject superseded completions. |
| Chat history snapshot | Messages, offers, revision, and saved outcome metadata from one chat version. Transaction retries return the successful attempt's snapshot. |
| Assistant session | Patient-scoped client state for history, drafts, offers, uncertain confirmations, and in-flight operations. Account changes and clears invalidate old callbacks. History and send responses cannot reduce the current revision; cached turn acknowledgments do not replace newer content. |

The booking module is in [appointments.ts](../functions/src/appointments.ts).
Its request resolution, reservation, and availability implementations are in
[appointments/](../functions/src/appointments/).
Chat history persistence is in [chatService.ts](../functions/src/assistant/chatService.ts),
and client session ownership is in
[assistant_chat_provider.dart](../lib/providers/assistant_chat_provider.dart).
