# SANITIZED-EVENT-READ-MODEL-01 dependency and legacy-read audit

This is a local implementation audit, not production authorization. Both rules
files retain `Bands/.read = auth != null`. Firebase Realtime Database grants
ancestor reads to every descendant, so **any signed-in user can still read
canonical Events, invitees, applications, RSVP comments, and other private
band descendants**. Projection rules can protect the new roots but cannot
reverse that legacy grant. The legacy grant blocks a final privacy release.

## Projection contracts

| Path | Reader | Writer | Allowlist and lifecycle |
| --- | --- | --- | --- |
| `bandMemberEvents/{bandId}/{eventId}` | Active exact-band member (`active`, `on_hold`, `temporarily_off`, or approved missing status) | Admin SDK only | `bandId`, `eventId`, `bandName`, `title`, `description`, `eventType`, `location`, `startDateTime`, `endDateTime`, `additionalNotes`, `createdBy`, `parentEventId`, `createdAt`, `updatedAt`, `rsvpDeadline`, `subEventSequence`, `requireResponse`, `isLocked`, `temporaryRoomId`, allowlisted rehearsal parts, and verified confirmed participants/assignments. No response collection, invitee map, applicant, or notification fields. Deleted or malformed source removes record. |
| `userEventReadModels/{uid}/{bandId}/{eventId}` | That UID only, with current canonical member or explicit manual invitation authority | Admin SDK only | Member fields plus only that UID's `Responses`, `ScheduleResponses`, exclusion, and manual invitation. Invite-only target gets no confirmed roster or assignment map. Removed authority deletes target record. |
| `bandManagerEvents/{bandId}/{eventId}` | Current active canonical Leader/Admin in exact band | Admin SDK only | Member fields plus allowlisted `Responses`, `ScheduleResponses`, exclusions, manual invites, verified assignment details, lock/reminder and edit metadata. Creator identity alone grants nothing. |
| `bandMemberCalendarEvents/{bandId}/{eventId}` | Active exact-band member | Admin SDK only | Allowlisted legacy `BandEvents/{bandId}/{eventId}` calendar fields (`Title`, `Description`, `Location`, `CreatorName`, `Date`, `StartTime`, `EndTime`, `IsFinalized`, `Type`, valid `ProposedDates`). No nested response or agreement data. |
| `eventReadProjectionIndex/{bandId}/{eventId}` | Server only | Admin SDK only | UID keys for stale-target deletion. |

The existing public Map Event feed is a separate projection and was not changed.
Legacy `BandEvents/PublishedSubRequests`, `SubRequestResponses`, notifications,
and agreements are not the private Band Event calendar feed.

## Function region contract

`mutateBandEvent` is an `onCall` export explicitly set to `europe-west1`.
`onBandEventReadModelWritten` and `onLegacyBandCalendarEventWritten` are the
only newly added deployable Event triggers. Each uses
`databaseTriggerRegion`, which resolves to `europe-west1` unless
`FUNCTIONS_EMULATOR` is exactly `true`; the local Functions emulator uses
`us-central1` for RTDB trigger routing. Ambient Database emulator host or hub
variables alone cannot change the deployable region. A source-level test
checks this and checks each Event trigger name is exported once. Region
routing creates no second deployed Event trigger. Source retries or concurrent
reconciliation may reattempt a value, so the reconciler compares the current
projection and writes only when its deterministic allowlisted value differs.

## Event dependency matrix

| Consumer | Before | Fields needed and audience | Current replacement / risk |
| --- | --- | --- | --- |
| Band Room Events/Gigs/Info | `Bands/{band}/Events` stream through `FirebaseService` | Schedule, card status, own RSVP, confirmed participant; active member | `bandMemberEvents` plus exact own `userEventReadModels`; a live exact own membership leaf clears the list on inactive/removal. Event ID preserved. Current manager-only Results navigation. |
| Event Details and ordinary notification navigation | Exact canonical Event and whole-band roster | Participant details, own RSVP, schedule, current manager gate | Exact member/own projections; a live exact own membership leaf clears former members. Route argument never displayed before authorized model. |
| Manage Events/Home private cards | Canonical Event list | Member event list, sorting and occurrence identity | `bandMemberEvents` plus own state; manager edit fetches exact `bandManagerEvents` after current authority check. |
| RSVP Results | Canonical Event and full roster | All RSVP values/comments, assignments, manager only | Destination checks current canonical Leader/Admin before `bandManagerEvents`; the live manager stream also watches only `Bands/{bandId}/Members_band/{uid}` and clears private results on role loss. No `initialEvent` read. Roster remains an exact canonical band read. |
| Create/Edit Event | Canonical Event parent | Editable metadata, manual invite list, excluded members, verified assignment metadata; manager only | Exact manager model; `mutateBandEvent` callable writes canonical Event after current manager authority. Own RSVP keeps exact leaf writes. |
| Find Substitute and SubRequest response details | Canonical Event lookup/list | Event identity and schedule; authorized manager or candidate | Member/own safe Event reads. SubRequest response aggregation retains one manager-gated exact canonical `externalInvitees` leaf pending coordinated response cutover. |
| Legacy Calendar route | `BandEvents/{bandId}` | Calendar entry fields; active member | `bandMemberCalendarEvents/{bandId}`. |
| RSVP and reminder backend | Canonical Event/Responses and band roster | Aggregate counts, reminders; Admin SDK | Server reads retained; no client authority from these reads. |
| Map Event projection backend | Whole `Bands/{bandId}` and exact canonical Event | Public Map source and membership inputs; Admin SDK | Existing behavior retained. Whole-band read must be split before a future least-privilege server/performance cutover. |

## Every remaining production direct `/Bands` reader

The list is grouped by call site; template paths with the same reader are one
entry. It excludes writes, `push().key` ID generation, trigger declarations,
and tests. The paths are still security-relevant because the broad ancestor
grant permits a caller to read more than the intended leaf.

| Production reader | Path and purpose | Planned replacement at coordinated legacy cutover |
| --- | --- | --- |
| `FirebaseService.getBandInfoAsync` | Individual `Bands/{bandId}/{metadata field}` leaves, including full `Members_band`; band details, not Event discovery | Safe public band profile plus exact owner/manager metadata and scoped roster models. |
| `FirebaseService.getBandMembersAsync` | `Bands/{bandId}/Members_band`; roster for manager and band views | Server-owned active roster projection with exact-band rules; keep exact authority leaf for guards. |
| `FirebaseService.getUserBandRoleAsync`, `canManageBandEventAsync`, `subscribeToBandEvent` startup | Exact `Bands/{bandId}/Members_band/{uid}` or Role leaf; current authority | Keep exact own membership leaf rule; remove root read inheritance. |
| `BandMembershipPolicy.readCanonicalBand` | Exact own membership, band Name, `isMock`, `isDemo` leaves | Keep own leaf rule and safe metadata projection. |
| `FirebaseService.getSubRequestResponsesAsync` | Exact `Bands/{bandId}/Events/{eventId}/externalInvitees` after SubRequest lookup and manager check; legacy response count | Dedicated manager-safe SubRequest response index; then remove this canonical read. |
| `FirebaseService.subscribeToGigsNews` | `Bands/{bandId}/GigsNews` | Scoped band-member news read rule/projection. |
| `FirebaseService.subscribeToBandEventRooms` | `Bands/{bandId}/eventRooms` | Scoped room list and membership rules. |
| `band_membership_index.reconcileMembershipIndex` | Exact member leaf and Name; server-owned index | Retain Admin SDK exact reads. |
| `membership_authority.requireManager` and mutation handler | Exact member leaf or whole band for managed mutation | Retain exact authority leaf; split whole-band mutation reads into necessary fields. |
| `event_read_models.reconcile/reconcileBand/reconcileLegacyCalendar` | Exact Event, Name, roster, per-band Events collection, legacy `BandEvents` source; server sanitization | Retain Admin SDK reads for projection; bound and paginate scans as needed. |
| `event_mutations.mutate` | Exact canonical Event and invitation leaf; manager mutation | Retain Admin SDK exact reads. |
| `index.js` city/band existence and catalogue trigger | Exact or whole band existence/source; server | Replace whole-band existence checks with Name or explicit marker. |
| `index.js` Event creation, response, reminder, staffing, agreement, membership, deletion and live callables | Exact Event and roster reads; several whole-band reads; scheduled reminder scans root `/Bands` | Keep server-only exact reads after splitting whole-band calls; reminder scan needs a server Event index. |
| `index.js` existing Map Event trigger | Whole `Bands/{bandId}` plus Event | Separate reviewed Map task; no change here. |
| `live_broadcasts.js` | Whole `Bands/{bandId}` and exact member leaf | Safe band metadata and exact member authority leaf. |

Backfill scripts use Admin SDK to scan canonical roots only when invoked with
explicit targets. They are not app or deployed request-path readers. The new
Event backfill is dry-run by default and was not pointed at production. Under
the owner's planned clean launch, this script remains a local/emulator
validation tool; no production legacy Event backfill is planned unless the
owner later authorizes one explicitly.

## Remaining direct canonical Event writes

`FirebaseService.updateEventResponseAsync` and
`updateScheduleItemResponseAsync` write only the caller's canonical RSVP leaf;
both rules files authorize only exact own leaves for active members or explicit
manual invitees, and deny the locked Event. `mutateBandEvent` performs manager
metadata/invite/lock/delete writes through Admin SDK. Existing SubRequest
compatibility writes to canonical `externalInvitees` remain in
`FirebaseService` as best-effort legacy code and require the later response
cutover; direct client writes are now denied. Backend assignment/revoke and
reminder triggers continue to write canonical leaves with Admin SDK.

## Clean-launch cutover and coordinated broad-grant removal plan

The owner plans a separately authorized complete account-and-data reset before
the major release. No reset, deletion, cleanup, migration, or production
backfill is authorized by this local task. Obsolete legacy Event, applicant,
response, agreement, and conversation records are not to be preserved or
migrated for that clean launch. Newly created data would still be exposed if
the broad authenticated `Bands/.read` grant remained, so removing that grant
is mandatory before final release even after the reset.

Legacy paths and consumers to retire after the safe client cutover and before
the separately authorized reset are:

| Legacy path | Remaining reader/writer to remove or replace |
| --- | --- |
| `Bands/{bandId}/Events/{eventId}` including `Responses`, `ScheduleResponses`, `externalInvitees`, `substituteAssignments`, excluded members and reminder state | `FirebaseService` own-RSVP leaf writes need a narrowly scoped rule or server mutation; manager-only Event administration and backend triggers need exact authority. The manager-gated legacy `getSubRequestResponsesAsync` external-invitee lookup needs a safe response index. |
| `BandEvents/{bandId}/{eventId}` private calendar entries | Legacy Calendar writer and any old client reader must retire in favor of the sanitized member calendar model. |
| `BandEvents/PublishedSubRequests`, `SubRequestResponses`, `CancelledSubRequests`, `Agreements`, and `Notifications` | SubRequest response, agreement, and notification clients and backend triggers require their own reviewed replacements or removal; the Event read-model task does not delete these records. |
| `Bands/{bandId}/Members_band`, `GigsNews`, and `eventRooms` | Exact membership guards remain; full roster, news, and room readers need scoped rules or models before the ancestor grant is removed. |
| Root `/Bands` server scans and whole-band reads | Scheduled reminders, Map Event projection, live broadcasts, catalogue reconciliation, and mutation helpers need exact indexes or scoped reads as separately reviewed work. |

Supported old client versions must be blocked through an approved minimum
version gate or made incompatible with removed legacy paths before the cutover.
The deletion inventory is a plan, not permission to remove any path now.

1. Inventory minimum supported client versions and every remaining direct
   `/Bands` consumer above, including old app builds. Replace full-band and
   roster readers with scoped read models, and the legacy response count with
   a manager-safe SubRequest model. Give legacy Calendar, event rooms, GigsNews,
   live broadcasts, Map backend, and scheduled reminders their exact policies
   or server indexes.
2. Validate projection writers, both rules sets, idempotence, and deletion
   behavior locally. Plan the separately authorized clean-launch reset and
   initialization of new read models for newly created records. Do not run a
   production legacy Event backfill under this plan.
3. Release clients using only safe models; prove no supported client depends on
   ancestor `/Bands` reads. Test old-client behavior explicitly or retire old
   versions through an approved minimum-version gate.
4. In both rules files, remove `Bands/.read = auth != null`, then add narrowly
   scoped reads for exact own membership, authorized band metadata/roster,
   event rooms and news, and approved manager canonical leaves. Test anonymous,
   unrelated, member, manager, former manager, invitee, applicant, and revoked
   roles against every ancestor and child. Verify unrelated authenticated
   canonical Event reads finally fail.
5. Roll out the rule change only after the preceding gates pass; monitor
   permission-denied rates and rollback criteria. Do not describe this local
   Event projection checkpoint as final production privacy enforcement.
