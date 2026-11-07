# AUTH-FEEDBACK-AND-MANAGE-GUARD-01 local audit

This is local implementation and review evidence, not release authorization. No commit, push, deployment, production access, data reset/deletion, migration/backfill, API enablement, production secret operation or version bump is authorized or performed by this task.

## Starting state and authorized scope

Starting branch: `main`. Starting HEAD: `ef78005a125bcef55ee29e4e8337f304e9435181`. Version: `2.79.3+252`. Working tree and staging were initially empty. All task changes remain unstaged and uncommitted.

The initial client audit identified a real-band creator bypass in both rules files. The owner explicitly authorized correcting both rules files and required emulator fixtures/tests. A second explicit authorization covers the existing `createMapPin`, `updateMapPin`, and `deleteMapPin` production callables under a separate Map ownership policy. Ordinary Map pins must not enter Manage Requests. Map UI/feed/audio/location/navigation behavior is preserved; the existing staffing action receives the requested authorization guard.

## Login audit and correction

`LoginScreen._handleLogin` previously relied on `AppState.isLoading`, while `AppState.login` set that flag before authenticating. `AuthGate` replaced LoginScreen with its loading scaffold, disposing the form/controllers and the presenter that was supposed to display the authentication error. The old screen matched exception strings and showed a transient snackbar. Keyboard submission and rapid duplicate submission did not share a synchronous guard.

The screen now owns attempt loading and a stable inline failure message. `AppState.login` retains profile/session clearing and profile loading, but no longer asks AuthGate to replace the form for an ordinary sign-in attempt. AppState accepts an optional FirebaseService dependency so tests exercise the actual AppState and AuthGate lifecycle. Production still defaults to the same FirebaseService.

Button and password-field Done/Enter use `_handleLogin`; a synchronous `_submitting` flag allows one request at a time. Email and the existing password-controller behavior survive failure. No raw Firebase exception/code, stack trace or password is displayed/logged by the login error handler. Retry clears the previous error. The error has a live-region Semantics node and remains until retry. Mounted checks discard disposed-screen results. Successful profile loading and `/main-nav` navigation remain intact. The registration-link row now wraps on narrow screens.

| FirebaseAuthException code | User-visible message |
|---|---|
| invalid-credential, wrong-password, user-not-found, invalid-login-credentials | Incorrect email or password. |
| invalid-email | Enter a valid email address. |
| too-many-requests | Too many attempts. Please try again later. |
| network-request-failed | Unable to connect. Check your internet connection. |
| user-disabled | This account has been disabled. |
| Any other code or non-Firebase exception | Unable to sign in right now. Please try again. |

Unknown-account and wrong-password feedback is identical. Local invalid-email validation uses the same message as the typed invalid-email exception.

## Former rules defect and final ownership policy

Both rules files previously granted `/SubRequests/$subRequestId` reads whenever any of `CreatorUserId`, `creatorUserId`, `UserId`, or `userId` equaled `auth.uid`, independently of the owning band's current canonical membership. RTDB ancestor-read inheritance also granted aggregate `Responses` access to an inactive, removed or demoted real-band creator.

The changed rule is only the `.read` at `/SubRequests/$subRequestId`. There is no new `/SubRequests` ancestor read. The corresponding read expression is identical in both files. Direct client writes to ownership/classification remain denied. The existing own-applicant leaf remains `/SubRequests/$subRequestId/Responses/$userId`, `.read: auth != null && auth.uid == $userId`, `.write: false`; the aggregate `.write` remains false.

| Record/caller | Canonical management / aggregate responses |
|---|---|
| Real band, exact canonical Leader/Admin with access-valid membership | Allowed |
| Real band, creator without current exact-band Leader/Admin | Denied |
| Ordinary Member, inactive, removed, conflicting role/status, unrelated or other-band manager | Denied |
| Explicit exact `freelance` or `standalone` marker, exact canonical creator | Allowed |
| Explicit personal staffing request, non-creator | Denied |
| Missing/empty/malformed/conflicting staffing BandId or missing/malformed/conflicting owner | Denied |
| Applicant | Own response leaf only, no aggregate/enumeration |
| Signed out | Denied |

Ownership uses canonical `BandId`/`bandId`; conflicting aliases fail closed. Creator fields are `CreatorUserId`/`creatorUserId`, then legacy `UserId`/`userId` and `createdBy`. Valid ownership must be server-verifiable. Absence of a band is never a freelance staffing marker. Canonical access status retains the existing shared policy: active, on_hold, temporarily_off, or missing legacy status; inactive/removed and conflicting aliases fail. A hold pauses RSVP obligations rather than band access. Roles use the existing `BandMembershipPolicy.canManageMember` and server membership authority, not a second role taxonomy.

Existing staffing callables still use `membershipAuthority.authorizeRequest`: existing-request publication, deleteSubRequest, assignment, revocation and agreement creation. Request/event identity mismatch remains denied server-side. Discovery still uses existing public/targeted/creator projections. No root canonical enumeration or legacy management fallback is added.

### Separate ordinary Map policy

`membershipAuthority.authorizeMapPin` is a module helper, not a new deployable export. The three existing deployable Map callables still explicitly use `europe-west1`.

* A missing band on an ordinary `map_pin`, or explicit `freelance`/`standalone`, is personal: only the exact creator may create/update/delete it. Being another band's manager grants nothing.
* Any real-band pin requires current canonical access-valid Leader/Admin of that exact band, including when the caller created the pin. Mere membership, stale Role, inactive status, removal, conflicting aliases and other-band authority fail.
* Empty, malformed, or reserved all-band identifiers do not become personal ownership.
* Ordinary Map pins are rejected by staffing management authorization regardless of creator/band role. Missing BandId never grants band authority or Manage Requests access.

The callable edits affect authorization only. Existing payload validation, field whitelist, projections, coordinates, audio and mutation operations remain intact. No ordinary Map UI edit/delete buttons, pin feed or navigation were redesigned.

## Complete Manage Requests entry and route inventory

| Entry | Source / final guard |
|---|---|
| Home active-request choice sheets (both existing implementations) | Selected canonical band; RequestManagementGate before Manage Active Requests action |
| Band Room menu Manage Sub Requests | Exact active band; RequestManagementGate |
| Find Musician top `manage_requests_btn` | Explicit route/selected band or explicit freelance context; RequestManagementGate |
| Find Musician active-request banner Manage button | Same exact context; RequestManagementGate |
| Find Gigs compact group/single Manage action | Exact primary request ID, band and creator hint; canonical request gate |
| Find Gigs group detail/slot picker action | Each individual request gets its own canonical request gate |
| Map staffing card Manage Request | Staffing-only branch; exact request gate. Ordinary Map pin controls unchanged |
| Notification Center sub_request_response/sub_response | Canonical pre-navigation authorization; destination independently repeats it |
| Active Requests View Responses | Per-request canonical check before preferences/notification side effects and navigation |
| Named `/sub-request-responses` route | Public SubRequestResponsesScreen always wraps the private body in the gate |
| Named `/sub-request-response-details` route | Public SubRequestResponseDetailsScreen always wraps the private body in the gate |
| Direct MaterialPageRoutes to either destination | Same public wrapper, no route-model authority |

No membership/access flow uses the catalogue as a membership source. Management uses `/userBandMembershipIndex/{uid}` candidates followed by exact `/Bands/{bandId}/Members_band/{uid}` validation and small canonical metadata leaves. No full `/Bands` or `/users` root read was introduced.

## Destination sequence and race protection

1. Capture user, selected band, route request/band/creator hints and a monotonic gate generation. Subscribe to identity changes before authorization.
2. For band context, resolve exact membership through the existing index and canonical membership check. Explicit freelance context is only a list context for that signed-in user's records.
3. For a request, read authorization metadata leaves only: BandId, bandId, CreatorUserId, creatorUserId, UserId, userId, createdBy, NotificationMode, notificationMode. Reject conflicting ownership, ordinary map_pin mode and route mismatches.
4. Apply exact manager or explicit creator policy. Only then read the canonical request body. Compare its metadata with the checked snapshot; discard changed ownership.
5. Begin private response/count/profile work only inside the authorized subtree. Never use passed Responses or a passed request body as a fallback. Revalidate each list candidate and its active lifecycle against canonical data before counts.
6. Watch canonical own membership and authorization metadata. Each managed list record has its own ownership watcher as well as response-count permission failure handling. Revoke on role/status/removal/ownership changes or stream failure.
7. Revocation marks a synchronous access token invalid before scheduling the frame that disposes the private subtree. This prevents queued completions from starting profile reads in the same event-loop turn. User/band/request changes and A-to-B-to-A transitions increment generations. Service-level identity tracking also rejects A-to-B-to-A even if the final UID matches again.
8. Selection/mutation/navigation rechecks canonical authority and drops disposed/stale work. The server independently enforces current authority for staffing mutations.

Denied destinations show a compact neutral message and safe Back navigation; no counts or cached private applicants remain. Denied entry actions disappear. Lookup infrastructure failure has neutral unavailable feedback without raw permission-denied text. Synchronous stream startup errors also fail closed. No canonical/legacy fallback is attempted after denial.

## Test integrity and intentional fixture changes

The focused suite runs the real LoginScreen/AppState/AuthGate and real service authorization through a read-only in-memory adapter. Its offline font fixture uses the Flutter SDK's bundled font for UI families; it does not fetch fonts, suppress Flutter errors, remove assertions or change production typography.

Existing presentation/lifecycle/Agreement tests now provide explicit authorized canonical fixtures and the new service contracts. Personal staffing fixtures use explicit freelance rather than missing/all band markers. Existing real-band positive fixtures declare exact manager authority. The old request-cards expectation that a creator immediately bypasses a pending role check was replaced with denial before and after a negative role result. Map's creator-positive test now declares an active exact-band manager and a separate new test proves creator-without-role denial. Existing behavioral assertions for response identity/counts, Agreement single assignment, no duplicate protected writes and Map Apply behavior are retained.

The old emulator expectation that an inactive real-band creator could still read responses was changed to assert permission denied. Positive personal fixtures now explicitly declare freelance ownership; canonical-conflict and malformed ownership negative tests remain. No production assertion was weakened just to obtain a passing test.

## Release limitations

* The clean parent has 334 Flutter failures. These remain a release-gate inventory; this task does not claim that the pre-existing application-wide failures are resolved. Any specific improvement is identified in the final comparison below.
* Notification-test timing sensitivity remains a release-gate item; one passing isolated run does not erase it.
* The separately authorized empty-data cutover and any deployment/release decision remain pending. No production legacy backfill, reset or cleanup was performed or authorized by this task.
* Local rules/emulator success establishes local behavior only. No production security/deployment state was inspected or asserted.
* Native screen-reader behavior and device-level keyboard/network behavior still require release QA; widget semantics, Enter, loading, error retention and narrow layouts have automated coverage.

## Final verification

All final checks are local. The complete Auth/Database/Functions emulator runner completed successfully with Node **22.13.1**: **841 passed, 0 failed, 0 skipped**, all 23 configured test files executed. Both rules variants' new authorization matrix passed **46/46**. The Map security file passed **32/32**, including 14 new explicit ownership cases. External suite network attempts: **0**; Cloud Secret Manager attempts: **0**. Existing loopback isolation and ADC/network guards were retained.

### Flutter totals and provenance

| Execution | Passed | Failed | Skipped |
|---|---:|---:|---:|
| Executed clean HEAD ef78005 | 1,076 | 334 | 0 |
| Complete current Flutter run before final list-race/routing-fixture reconciliation | 1,123 | 334 | 0 |
| Final six affected suites after those corrections | 175 | 6 | 0 |
| Final results by test identity, replacing affected-file results with the final rerun | **1,126** | **333** | **0** |
| Focused AUTH-FEEDBACK-AND-MANAGE-GUARD suite (included above) | **48** | **0** | **0** |

The six failures in the final affected rerun are the pre-existing `subrequest_hotfix_visibility_test.dart` failures, with matching clean-HEAD names and normalized causes. The final affected rerun includes the new suite, Manage Requests lifecycle, request cards, clean-schema privacy, legacy hotfix visibility and FindSub routing/banner suites. No failures were skipped. These reconciled totals are explicitly a full run plus affected reruns, not a claim that one raw process produced the combined totals.

Every one of the **333 remaining failures** has the same test name and normalized failure cause at clean HEAD. **Zero new failing names; zero changed remaining failure causes.** Normalization removes checkout prefixes, stack line/column offsets and generated Flutter object hashes; it preserves assertion messages, expected/actual values and substantive errors. The parent archive's reviewed files were checked against Git and had zero mismatches.

One prior failure is now fixed: `widget_test.dart — Login screen elements smoke test`. Clean HEAD overflowed its registration-link Row by 104 pixels; the task's narrow-screen Wrap correction makes the unchanged smoke assertion pass. The original 334-item baseline remains documented; 333 failures remain unresolved release work.

Last review additionally tested returning from an isolated detail route after logout and ownership loss while a delete confirmation remains open. A disposed list no longer reloads, and a revoked confirmation issues zero delete calls. Deletion errors use neutral feedback and canonical ownership is rechecked before mutation.

Raw evidence remains in ignored build files: `auth-guard-head.jsonl`, `auth-guard-current.jsonl`, `auth-guard-final-races.jsonl`, `auth-guard-final-comparison.json`, `auth-guard-analyzer-comparison.json`, `auth-guard-flutter-analyze-final.txt`, and `emulator-isolation-{gate.log,results.json,summary.json}`. No build output or generated test-result file is part of the source change list.

### Analysis and integrity

| Check | Result |
|---|---|
| Flutter analyze --no-pub, every changed production Dart file | 0 errors, 14 warnings, 222 infos |
| Same files at clean HEAD | 0 errors, 14 warnings, 222 infos |
| New diagnostics by file/code/message, ignoring positions and CLI terminal punctuation | **0** |
| node --check, all 7 changed/new JavaScript files | Pass |
| Both rules files and Functions package JSON parsing | Pass |
| Changed tracked Python | None; Python compile gate not applicable |
| git diff --check | Pass |
| Credential/private-key/token pattern scan and changed-file review | No credentials, secrets, environment files, logs, build output or temporary artifacts included |
| Functions package change | Only new emulator test-suite registration |

Changed production Dart files analyzed:

- `lib/models/request_management_access.dart`
- `lib/providers/app_state.dart`
- `lib/services/firebase_service.dart`
- `lib/utils/login_feedback.dart`
- `lib/views/band_room_chat_screen.dart`
- `lib/views/find_gigs_screen.dart`
- `lib/views/find_sub_screen.dart`
- `lib/views/home_screen.dart`
- `lib/views/login_screen.dart`
- `lib/views/notification_center_screen.dart`
- `lib/views/sub_request_response_details_screen.dart`
- `lib/views/sub_request_responses_screen.dart`
- `lib/widgets/map_pin_details_card.dart`
- `lib/widgets/request_management_gate.dart`

### Firebase per-file totals

| Test file | Passed | Failed | Skipped |
|---|---:|---:|---:|
| `test/backfill_event_read_models.test.js` | 2 | 0 | 0 |
| `test/backfill_map_event_feed.test.js` | 10 | 0 | 0 |
| `test/backfill_public_map_pin_feed.test.js` | 7 | 0 | 0 |
| `test/band_membership_index.test.js` | 27 | 0 | 0 |
| `test/catalogue_projections.test.js` | 51 | 0 | 0 |
| `test/city_verification.test.js` | 6 | 0 | 0 |
| `test/emulator_auth_manage_guard.test.js` | 46 | 0 | 0 |
| `test/emulator_band_membership_index.test.js` | 13 | 0 | 0 |
| `test/emulator_callables.test.js` | 84 | 0 | 0 |
| `test/emulator_catalogue_projections.test.js` | 24 | 0 | 0 |
| `test/emulator_city_verification.test.js` | 12 | 0 | 0 |
| `test/emulator_clean_schema_privacy.test.js` | 22 | 0 | 0 |
| `test/emulator_event_map_feed.test.js` | 19 | 0 | 0 |
| `test/emulator_event_read_models.test.js` | 13 | 0 | 0 |
| `test/emulator_isolation.test.js` | 3 | 0 | 0 |
| `test/emulator_map_pin_security.test.js` | 32 | 0 | 0 |
| `test/emulator_membership_authority.test.js` | 106 | 0 | 0 |
| `test/emulator_rules.test.js` | 214 | 0 | 0 |
| `test/event_read_models.test.js` | 7 | 0 | 0 |
| `test/functions_logic.test.js` | 100 | 0 | 0 |
| `test/google_places_cities.test.js` | 21 | 0 | 0 |
| `test/subrequest_security.test.js` | 14 | 0 | 0 |
| `test/verify_subrequest_migration.test.js` | 8 | 0 | 0 |

### Complete Flutter per-file totals on final source

| Test file | Passed | Failed | Skipped |
|---|---:|---:|---:|
| `account_and_band_deletion_test.dart` | 2 | 5 | 0 |
| `agreement_integrity_01_test.dart` | 28 | 0 | 0 |
| `agreements_ux_01a_test.dart` | 28 | 0 | 0 |
| `applied_lifecycle_01_test.dart` | 34 | 0 | 0 |
| `auth_feedback_and_manage_guard_01_test.dart` | 48 | 0 | 0 |
| `band_event_test.dart` | 10 | 0 | 0 |
| `band_member_hold_test.dart` | 2 | 3 | 0 |
| `band_membership_performance_01_test.dart` | 42 | 0 | 0 |
| `band_required_prompt_01_test.dart` | 33 | 0 | 0 |
| `band_room_files_category_test.dart` | 4 | 0 | 0 |
| `band_room_gigs_info_feed_test.dart` | 0 | 3 | 0 |
| `band_section_chat_test.dart` | 8 | 0 | 0 |
| `chat_architecture_test.dart` | 4 | 0 | 0 |
| `clean_schema_privacy_01_test.dart` | 8 | 0 | 0 |
| `collabs_landing_picker_test.dart` | 1 | 2 | 0 |
| `config/feature_flags_live_broadcast_test.dart` | 2 | 0 | 0 |
| `create_01_event_session_test.dart` | 15 | 9 | 0 |
| `create_edit_band_feedback_test.dart` | 1 | 10 | 0 |
| `create_event_edit_members_test.dart` | 1 | 4 | 0 |
| `currency_formatter_test.dart` | 3 | 0 | 0 |
| `edit_band_settings_test.dart` | 4 | 8 | 0 |
| `event_details_page_rsvp_test.dart` | 10 | 0 | 0 |
| `event_results_page_test.dart` | 10 | 0 | 0 |
| `find_gigs_feed_test.dart` | 0 | 12 | 0 |
| `find_musician_02_test.dart` | 14 | 21 | 0 |
| `find_musician_03a_test.dart` | 0 | 21 | 0 |
| `find_musician_03b_test.dart` | 1 | 40 | 0 |
| `find_musician_04_test.dart` | 3 | 16 | 0 |
| `find_musician_ux_01_test.dart` | 25 | 0 | 0 |
| `find_requests_01b_test.dart` | 2 | 16 | 0 |
| `find_sub_routing_and_banner_test.dart` | 2 | 0 | 0 |
| `gen_01_selection_field_tap_test.dart` | 8 | 2 | 0 |
| `gen_batch_ui_test.dart` | 1 | 7 | 0 |
| `gig_map_guide_banner_test.dart` | 1 | 0 | 0 |
| `gig_map_pin_color_coding_test.dart` | 8 | 0 | 0 |
| `global_create_event_phase1_test.dart` | 10 | 2 | 0 |
| `home_activity_badges_test.dart` | 10 | 6 | 0 |
| `home_profiles_action_label_test.dart` | 2 | 0 | 0 |
| `inbox_null_timestamp_test.dart` | 1 | 0 | 0 |
| `instruments_list_update_test.dart` | 0 | 2 | 0 |
| `international_city_forms_01_test.dart` | 7 | 0 | 0 |
| `international_city_picker_01_test.dart` | 7 | 0 | 0 |
| `manage_events_screen_test.dart` | 5 | 0 | 0 |
| `manage_requests_lifecycle_01_test.dart` | 48 | 0 | 0 |
| `map_event_activity_helper_test.dart` | 20 | 0 | 0 |
| `map_event_feed_test.dart` | 9 | 0 | 0 |
| `map_view_apply_test.dart` | 24 | 0 | 0 |
| `map_view_audio_focus_test.dart` | 20 | 0 | 0 |
| `map_view_backend_persistence_test.dart` | 11 | 0 | 0 |
| `map_view_feed_test.dart` | 0 | 1 | 0 |
| `map_view_feedback_04_test.dart` | 18 | 0 | 0 |
| `map_view_lifecycle_test.dart` | 6 | 0 | 0 |
| `map_view_light_version_test.dart` | 8 | 0 | 0 |
| `map_view_quick_polish_test.dart` | 12 | 0 | 0 |
| `map_view_snippet_crosshair_test.dart` | 6 | 0 | 0 |
| `map_view_unified_feed_test.dart` | 30 | 0 | 0 |
| `map_view_upload_parity_test.dart` | 17 | 0 | 0 |
| `marketplace_redesign_test.dart` | 7 | 9 | 0 |
| `membership_authority_hardening_01_test.dart` | 60 | 0 | 0 |
| `models/live_broadcast_test.dart` | 5 | 0 | 0 |
| `multi_subs_01_test.dart` | 12 | 35 | 0 |
| `new_user_skills_and_band_guards_01_test.dart` | 35 | 0 | 0 |
| `notification_center_test.dart` | 16 | 2 | 0 |
| `oct_sprint_01_events_calendar_test.dart` | 0 | 14 | 0 |
| `p2_tasks_ui_cleanup_test.dart` | 1 | 4 | 0 |
| `profile_details_feedback_test.dart` | 0 | 8 | 0 |
| `profile_social_links_test.dart` | 0 | 2 | 0 |
| `profiles_picker_popup_test.dart` | 2 | 0 | 0 |
| `public_event_calendar_feedback_test.dart` | 0 | 18 | 0 |
| `public_event_calendar_repository_test.dart` | 10 | 0 | 0 |
| `public_event_calendar_screen_test.dart` | 0 | 16 | 0 |
| `public_event_create_test.dart` | 4 | 4 | 0 |
| `public_event_details_screen_test.dart` | 1 | 9 | 0 |
| `push_sound_admin_screen_test.dart` | 4 | 0 | 0 |
| `registration_flow_test.dart` | 5 | 0 | 0 |
| `registration_genres_test.dart` | 7 | 1 | 0 |
| `registration_secondary_skills_01_test.dart` | 49 | 0 | 0 |
| `request_cards_01_test.dart` | 60 | 0 | 0 |
| `rsvp_deadline_utils_test.dart` | 14 | 0 | 0 |
| `rsvp_design_03_test.dart` | 3 | 6 | 0 |
| `ruta_02_picker_hierarchy_test.dart` | 24 | 2 | 0 |
| `safe_catalogue_projections_01_test.dart` | 31 | 0 | 0 |
| `sanitized_event_read_model_01_test.dart` | 7 | 0 | 0 |
| `services/live_broadcast_service_test.dart` | 2 | 0 | 0 |
| `services/livekit_audio_controller_test.dart` | 6 | 0 | 0 |
| `services/mock_rehearsal_volume_test.dart` | 4 | 0 | 0 |
| `session_01_create_session_test.dart` | 14 | 0 | 0 |
| `simple_rsvp_02_test.dart` | 3 | 2 | 0 |
| `skills_taxonomy_test.dart` | 23 | 1 | 0 |
| `sub_request_location_override_regression_test.dart` | 7 | 0 | 0 |
| `sub_request_self_response_test.dart` | 4 | 0 | 0 |
| `subrequest_data_consistency_01_test.dart` | 12 | 0 | 0 |
| `subrequest_feed_client_test.dart` | 11 | 0 | 0 |
| `subrequest_hotfix_visibility_test.dart` | 9 | 6 | 0 |
| `subrequest_response_count_test.dart` | 1 | 0 | 0 |
| `task4_navigation_audio_test.dart` | 4 | 0 | 0 |
| `today_features_test.dart` | 0 | 4 | 0 |
| `tour_group_rendering_test.dart` | 4 | 0 | 0 |
| `user_profile_test.dart` | 3 | 0 | 0 |
| `utils/geo_distance_test.dart` | 2 | 0 | 0 |
| `utils/map_crosshair_targeting_test.dart` | 12 | 0 | 0 |
| `widget_test.dart` | 1 | 0 | 0 |
| `widgets/live_broadcaster_bar_test.dart` | 3 | 0 | 0 |
| `widgets/live_listener_sheet_test.dart` | 2 | 0 | 0 |
| `widgets/map_crosshair_test.dart` | 3 | 0 | 0 |
| `widgets/rsvp_reminder_dialog_test.dart` | 5 | 0 | 0 |

### Exact focused test names

- ABA during authorization prevents full canonical or private reads — passed
- ABA user switch clears rendered private applicant — passed
- Admin sees action and opens guarded canonical detail — passed
- Leader sees action and opens guarded canonical detail — passed
- access error clears rendered private applicant — passed
- band during authorization prevents full canonical or private reads — passed
- band switch clears rendered private applicant — passed
- button and Enter rapid repeats share one request; success navigation retained — passed
- closing detail after logout cannot refresh a disposed management list — passed
- conflicting band denies detail and reads no private payload — passed
- conflicting roles: hidden action and direct route denied without private reads — passed
- conflicting statuses: hidden action and direct route denied without private reads — passed
- empty band denies detail and reads no private payload — passed
- forged route payload and response cache never replace canonical data — passed
- freelance exact creator allowed without band authority — passed
- inactive creator: hidden action and direct route denied without private reads — passed
- invalid email validation and 320px login layout — passed
- login invalid-credential: stable form, private accessible error and retained email — passed
- login invalid-email: stable form, private accessible error and retained email — passed
- login invalid-login-credentials: stable form, private accessible error and retained email — passed
- login network-request-failed: stable form, private accessible error and retained email — passed
- login too-many-requests: stable form, private accessible error and retained email — passed
- login unexpected: stable form, private accessible error and retained email — passed
- login user-disabled: stable form, private accessible error and retained email — passed
- login user-not-found: stable form, private accessible error and retained email — passed
- login wrong-password: stable form, private accessible error and retained email — passed
- logout clears rendered private applicant — passed
- logout during authorization prevents full canonical or private reads — passed
- lookup error denies detail and reads no private payload — passed
- malformed band denies detail and reads no private payload — passed
- missing band denies detail and reads no private payload — passed
- missing list band denied before feeds or counts; compact Back safe at 320px — passed
- missing owner denies detail and reads no private payload — passed
- noncreator freelance denies detail and reads no private payload — passed
- ordinary Member: hidden action and direct route denied without private reads — passed
- ordinary band-owned Map pins absent from management list — passed
- ordinary map pin denies detail and reads no private payload — passed
- other band manager denies detail and reads no private payload — passed
- ownership loss during delete confirmation prevents mutation — passed
- removed creator: hidden action and direct route denied without private reads — passed
- request ownership revocation clears list even while band manager remains authorized — passed
- revocation and pending response completion in same turn cannot start profiles — passed
- role loss clears rendered private applicant — passed
- signed out denies detail and reads no private payload — passed
- standalone exact creator allowed without band authority — passed
- user switch clears rendered private applicant — passed
- wrong route band denies detail and reads no private payload — passed
- wrong route creator denies detail and reads no private payload — passed

### Every remaining failure and clean-HEAD comparison

| Test file | Exact failing test name | Same normalized cause at clean HEAD |
|---|---|---|
| `account_and_band_deletion_test.dart` | Delete Account UI Tests 1. CustomTopBar settings menu displays "Delete Account" and opens confirmation dialog | Yes |
| `account_and_band_deletion_test.dart` | Delete Account UI Tests 2. EditProfileScreen displays Danger Zone with "Delete Account" button and opens confirmation | Yes |
| `account_and_band_deletion_test.dart` | EditBandInfoScreen Delete Band Tests 1. Shows "Delete Band" button when current user is Leader | Yes |
| `account_and_band_deletion_test.dart` | EditBandInfoScreen Delete Band Tests 2. Hides "Delete Band" button when current user is NOT Leader | Yes |
| `account_and_band_deletion_test.dart` | EditBandInfoScreen Delete Band Tests 3. Tapping "Delete Band" displays confirmation dialog and calls deleteBand on confirm | Yes |
| `band_member_hold_test.dart` | BandRoomChatScreen On Hold UI tests Leader can toggle member on-hold status | Yes |
| `band_member_hold_test.dart` | BandRoomChatScreen On Hold UI tests renders ON HOLD badge on on-hold members in Members tab | Yes |
| `band_member_hold_test.dart` | EditBandInfoScreen On Hold UI tests displays ON HOLD badge for on-hold members in EditBandInfoScreen | Yes |
| `band_room_gigs_info_feed_test.dart` | Direct 1-tap RSVP saves response and chronology sorts upcoming ascending and past descending | Yes |
| `band_room_gigs_info_feed_test.dart` | Gigs/Info event card is whole clickable, has chevron, no RSVP button, opens EventResultsPage | Yes |
| `band_room_gigs_info_feed_test.dart` | Gigs/Info sub-tabs: Events (left) & Other (right), sub-filters Upcoming & Past, and newest first sorting | Yes |
| `collabs_landing_picker_test.dart` | Collabs Landing Screen & Master Category Verification Tests CollabsLandingScreen Select Favorites: Select all, Clear all, deselection, duplicate avoidance, and publishing | Yes |
| `collabs_landing_picker_test.dart` | Collabs Landing Screen & Master Category Verification Tests FindCollabsScreen Select Favorites: Select all and Clear all functionality | Yes |
| `create_01_event_session_test.dart` | CREATE-01 — Global Launcher & Event Types Tests 19, 20. RSVP validation: custom mode empty/invalid blocks save, valid positive hours calculates deadline | Yes |
| `create_01_event_session_test.dart` | CREATE-01 — Global Launcher & Event Types Tests 24, 25. BandRoom "Create Event" button opens creation page with clean taxonomy | Yes |
| `create_01_event_session_test.dart` | CREATE-01 — Global Launcher & Event Types Tests 26. SIMPLE-EVENT-01: Publishing event saves exactly ONE BandEvent with attached rehearsals array and creates 1 chat room | Yes |
| `create_01_event_session_test.dart` | CREATE-01 — Global Launcher & Event Types Tests 27. SIMPLE-EVENT-01: Existing event with rehearsals loads into form and allows saving modifications | Yes |
| `create_01_event_session_test.dart` | CREATE-01 — Global Launcher & Event Types Tests 28. SIMPLE-EVENT-01: Responsive test at 320 px width ensures no layout overflow | Yes |
| `create_01_event_session_test.dart` | CREATE-01 — Global Launcher & Event Types Tests 5. Create Event requires band selection and opens Band Event form | Yes |
| `create_01_event_session_test.dart` | CREATE-01 — Global Launcher & Event Types Tests 8, 9, 10. Create Event has removed Event Type dropdown and Multiple Events toggle, with hint e.g. Club gig – Summer Tour | Yes |
| `create_01_event_session_test.dart` | CREATE-01 — Global Launcher & Event Types Tests RSVP preset option: No automatic Reminders | Yes |
| `create_01_event_session_test.dart` | CREATE-01 — Global Launcher & Event Types Tests RSVP preset option: predefined 48 hours | Yes |
| `create_edit_band_feedback_test.dart` | Create and Edit Band Focused Owner-Feedback Tests 1. About appears directly after Band Name in CreateBandScreen | Yes |
| `create_edit_band_feedback_test.dart` | Create and Edit Band Focused Owner-Feedback Tests 1b. About appears directly after Band Name in EditBandInfoScreen | Yes |
| `create_edit_band_feedback_test.dart` | Create and Edit Band Focused Owner-Feedback Tests 2. No duplicate About field remains in Create and Edit Band | Yes |
| `create_edit_band_feedback_test.dart` | Create and Edit Band Focused Owner-Feedback Tests 3. Rehearsal schedule is disabled and hidden by default in Create Band | Yes |
| `create_edit_band_feedback_test.dart` | Create and Edit Band Focused Owner-Feedback Tests 4. Enabling switch displays Day, Start Time, and End Time; toggling off hides them | Yes |
| `create_edit_band_feedback_test.dart` | Create and Edit Band Focused Owner-Feedback Tests 5. A saved schedule reopens correctly in Edit Band; bands without schedule open off | Yes |
| `create_edit_band_feedback_test.dart` | Create and Edit Band Focused Owner-Feedback Tests 6a. Saving with switch off does not store default values in CreateBandScreen | Yes |
| `create_edit_band_feedback_test.dart` | Create and Edit Band Focused Owner-Feedback Tests 6b. Saving with switch off does not store default values in EditBandInfoScreen | Yes |
| `create_edit_band_feedback_test.dart` | Create and Edit Band Focused Owner-Feedback Tests 7. Schedule appears below Rehearsal Location and above Map View location | Yes |
| `create_edit_band_feedback_test.dart` | Create and Edit Band Focused Owner-Feedback Tests 8. Exact disclaimer heading and body are displayed in Create Band and Edit Band | Yes |
| `create_event_edit_members_test.dart` | CreateEventPage Edit Band Members Widget Tests Adding guest musician adds to externalInvitees and displays guest badge | Yes |
| `create_event_edit_members_test.dart` | CreateEventPage Edit Band Members Widget Tests Date range is automatically derived from sub-events/rehearsals | Yes |
| `create_event_edit_members_test.dart` | CreateEventPage Edit Band Members Widget Tests Displays expandable Edit Band Members card with members and add guest button | Yes |
| `create_event_edit_members_test.dart` | CreateEventPage Edit Band Members Widget Tests Toggling member off excludes them from event and saves excludedMemberIds | Yes |
| `edit_band_settings_test.dart` | EDIT-BAND-01: Band.canUserEdit Unit Tests canUserEdit respects band userRole fallback | Yes |
| `edit_band_settings_test.dart` | EDIT-BAND-01: Map View Explanatory Text Map View explanatory text appears in CreateBandScreen directly beneath correct field | Yes |
| `edit_band_settings_test.dart` | EDIT-BAND-01: Map View Explanatory Text Map View explanatory text appears in EditBandInfoScreen directly beneath correct field | Yes |
| `edit_band_settings_test.dart` | EDIT-BAND-01: Regular Settings Menu & Edit Band /edit-band route successfully opens EditBandInfoScreen | Yes |
| `edit_band_settings_test.dart` | EDIT-BAND-01: Regular Settings Menu & Edit Band Edit Band is shown in regular Settings menu and prompts to choose band to edit | Yes |
| `edit_band_settings_test.dart` | EDIT-BAND-02: Band Members Management on EditBandInfoScreen EditBandInfoScreen allows adding a new member via Add Member dialog | Yes |
| `edit_band_settings_test.dart` | EDIT-BAND-02: Band Members Management on EditBandInfoScreen EditBandInfoScreen allows removing a member with confirmation dialog | Yes |
| `edit_band_settings_test.dart` | EDIT-BAND-02: Band Members Management on EditBandInfoScreen EditBandInfoScreen displays BAND MEMBERS section with members and details | Yes |
| `find_gigs_feed_test.dart` | FIND-GIGS-01A Specification Verification 1. Tabs are exactly Substitute Requests, New Member Requests, and Saved | Yes |
| `find_gigs_feed_test.dart` | FIND-GIGS-01A Specification Verification 10. Nearest upcoming request remains sorted first | Yes |
| `find_gigs_feed_test.dart` | FIND-GIGS-01A Specification Verification 2 & 3. Substitute and New Member classification and Direct Invitations without duplicates | Yes |
| `find_gigs_feed_test.dart` | FIND-GIGS-01A Specification Verification 2b. New Member classification is case-insensitive and whitespace-tolerant | Yes |
| `find_gigs_feed_test.dart` | FIND-GIGS-01A Specification Verification 4 & 5. Single grouped request does not show 1 event · 1 position and shows Role / Instrument | Yes |
| `find_gigs_feed_test.dart` | FIND-GIGS-01A Specification Verification 6. Details sheet hides Event #1 for single event but retains numbering for two events | Yes |
| `find_gigs_feed_test.dart` | FIND-GIGS-01A Specification Verification 7 & 8. Unpaid requests show no badge/text; Paid requests retain amount and Details | Yes |
| `find_gigs_feed_test.dart` | FIND-GIGS-01A Specification Verification 9. Page renders at 320 px width without overflow | Yes |
| `find_gigs_feed_test.dart` | FindGigsScreen displays Electric Guitar subrequest for Guitarist user | Yes |
| `find_gigs_feed_test.dart` | FindGigsScreen displays all gigs if user has no instruments set | Yes |
| `find_gigs_feed_test.dart` | FindGigsScreen displays today gig with ISO string for user with mainInstrument | Yes |
| `find_gigs_feed_test.dart` | FindGigsScreen filters out cancelled and deleted gigs | Yes |
| `find_musician_02_test.dart` | FIND-MUSICIAN-02: Favorites Search & Selection Controls 21. Favorites section shows prominent header, checkboxes, and + Add Favorite(s) | Yes |
| `find_musician_02_test.dart` | FIND-MUSICIAN-02: Favorites Search & Selection Controls 22. Selecting a favorite collapses list, displays Chosen Substitute, and clearing removes it | Yes |
| `find_musician_02_test.dart` | FIND-MUSICIAN-02: Favorites Search & Selection Controls 23. Searching and adding musician via + Add Favorite(s) adds to global favorites | Yes |
| `find_musician_02_test.dart` | FIND-MUSICIAN-02: FindGigsScreen Grouped Multiple Requests 24. Renders one grouped card with payment amount and positions summary | Yes |
| `find_musician_02_test.dart` | FIND-MUSICIAN-02: FindGigsScreen Grouped Multiple Requests 25. Tapping grouped card opens bottom sheet showing each event occurrence and position | Yes |
| `find_musician_02_test.dart` | FIND-MUSICIAN-02: FindGigsScreen Grouped Multiple Requests 27. Resolves same occurrences in correct order when opened from parent event, event 1, or event 2 | Yes |
| `find_musician_02_test.dart` | FIND-MUSICIAN-02: FindGigsScreen Grouped Multiple Requests 29. Cancelling or updating one slot preserves RequestGroupId and grouped card | Yes |
| `find_musician_02_test.dart` | FIND-MUSICIAN-02: FindGigsScreen Grouped Multiple Requests 31. Legacy SubRequests without RequestGroupId render cleanly as individual singleton groups | Yes |
| `find_musician_02_test.dart` | FIND-MUSICIAN-02: FindGigsScreen Grouped Multiple Requests 32. Before any SubRequests exist: opening parent, child 1, or child 2 derives identical RequestGroupId | Yes |
| `find_musician_02_test.dart` | FIND-MUSICIAN-02: FindGigsScreen Grouped Multiple Requests 33. Header-only parent event is excluded from occurrences list; only child occurrences render as Event 1, Event 2 | Yes |
| `find_musician_02_test.dart` | FIND-MUSICIAN-02: FindSubScreen Multi-Event Hierarchy & Streamlined UI 10. Displays FIND MUSICIAN/VOCALIST title and mode switcher | Yes |
| `find_musician_02_test.dart` | FIND-MUSICIAN-02: FindSubScreen Multi-Event Hierarchy & Streamlined UI 11. Displays only the band name in band context area (no Staffing for...) | Yes |
| `find_musician_02_test.dart` | FIND-MUSICIAN-02: FindSubScreen Multi-Event Hierarchy & Streamlined UI 12. Renames heading to Date & Time | Yes |
| `find_musician_02_test.dart` | FIND-MUSICIAN-02: FindSubScreen Multi-Event Hierarchy & Streamlined UI 13. Redundant top staffing summary box is absent | Yes |
| `find_musician_02_test.dart` | FIND-MUSICIAN-02: FindSubScreen Multi-Event Hierarchy & Streamlined UI 14. Resolves and displays each child event in Multiple Event with shortened title and sequence | Yes |
| `find_musician_02_test.dart` | FIND-MUSICIAN-02: FindSubScreen Multi-Event Hierarchy & Streamlined UI 15. Slot numbering restarts per event occurrence (single slot hides number) | Yes |
| `find_musician_02_test.dart` | FIND-MUSICIAN-02: FindSubScreen Multi-Event Hierarchy & Streamlined UI 16. Adds substitute slot to specific event occurrence when + ADD SUBSTITUTE is tapped | Yes |
| `find_musician_02_test.dart` | FIND-MUSICIAN-02: FindSubScreen Multi-Event Hierarchy & Streamlined UI 17. Description field has visible label Description | Yes |
| `find_musician_02_test.dart` | FIND-MUSICIAN-02: FindSubScreen Multi-Event Hierarchy & Streamlined UI 18. Paid Gig toggle shows Amount input field with SEK prefix | Yes |
| `find_musician_02_test.dart` | FIND-MUSICIAN-02: FindSubScreen Multi-Event Hierarchy & Streamlined UI 19. Primary action displays PUBLISH MULTIPLE REQUEST when multiple slots exist | Yes |
| `find_musician_02_test.dart` | FIND-MUSICIAN-02: FindSubScreen Multi-Event Hierarchy & Streamlined UI 20. Publishing saves all slots with same RequestGroupId, EventSequence, and PayAmount | Yes |
| `find_musician_03a_test.dart` | FIND-MUSICIAN-03A.1 Entry Context & Request Snapshot Tests 1. HomeView/standalone entry renders current hierarchy without legacy event headers | Yes |
| `find_musician_03a_test.dart` | FIND-MUSICIAN-03A.1 Entry Context & Request Snapshot Tests 10. Switching modes preserves the request draft | Yes |
| `find_musician_03a_test.dart` | FIND-MUSICIAN-03A.1 Entry Context & Request Snapshot Tests 11. Event 1 and Event 2 maintain independent editable values | Yes |
| `find_musician_03a_test.dart` | FIND-MUSICIAN-03A.1 Entry Context & Request Snapshot Tests 12. Publishing Event 1 slots uses Event 1 request snapshot | Yes |
| `find_musician_03a_test.dart` | FIND-MUSICIAN-03A.1 Entry Context & Request Snapshot Tests 13. Publishing Event 2 slots uses Event 2 request snapshot | Yes |
| `find_musician_03a_test.dart` | FIND-MUSICIAN-03A.1 Entry Context & Request Snapshot Tests 14. A new standalone slot does not display Assigned substitute or empty box | Yes |
| `find_musician_03a_test.dart` | FIND-MUSICIAN-03A.1 Entry Context & Request Snapshot Tests 15. An existing unassigned slot does not display the empty assignment box | Yes |
| `find_musician_03a_test.dart` | FIND-MUSICIAN-03A.1 Entry Context & Request Snapshot Tests 16. Favorite or applicant selection alone does not display the assignment section | Yes |
| `find_musician_03a_test.dart` | FIND-MUSICIAN-03A.1 Entry Context & Request Snapshot Tests 17. A successfully assigned slot displays Assigned substitute and Assigned: <name> | Yes |
| `find_musician_03a_test.dart` | FIND-MUSICIAN-03A.1 Entry Context & Request Snapshot Tests 17b. Slot with status assigned but null or empty assignedUserId does not display Assigned substitute section | Yes |
| `find_musician_03a_test.dart` | FIND-MUSICIAN-03A.1 Entry Context & Request Snapshot Tests 18. Revoke remains functional and revoking the assignment hides the section again | Yes |
| `find_musician_03a_test.dart` | FIND-MUSICIAN-03A.1 Entry Context & Request Snapshot Tests 19. Required standalone fields block invalid publication | Yes |
| `find_musician_03a_test.dart` | FIND-MUSICIAN-03A.1 Entry Context & Request Snapshot Tests 2. Standalone entry allows selecting Request Type | Yes |
| `find_musician_03a_test.dart` | FIND-MUSICIAN-03A.1 Entry Context & Request Snapshot Tests 20. Narrow 320px layout renders without throwing any Flutter layout or render exceptions | Yes |
| `find_musician_03a_test.dart` | FIND-MUSICIAN-03A.1 Entry Context & Request Snapshot Tests 3. Standalone Event Type begins unselected and is selectable | Yes |
| `find_musician_03a_test.dart` | FIND-MUSICIAN-03A.1 Entry Context & Request Snapshot Tests 4. Other standalone event fields begin blank | Yes |
| `find_musician_03a_test.dart` | FIND-MUSICIAN-03A.1 Entry Context & Request Snapshot Tests 5. Existing-event entry pre-fills all event fields | Yes |
| `find_musician_03a_test.dart` | FIND-MUSICIAN-03A.1 Entry Context & Request Snapshot Tests 6. Existing-event Description can be edited as request-local data | Yes |
| `find_musician_03a_test.dart` | FIND-MUSICIAN-03A.1 Entry Context & Request Snapshot Tests 7. Existing-event Event Type can be changed as request-local data | Yes |
| `find_musician_03a_test.dart` | FIND-MUSICIAN-03A.1 Entry Context & Request Snapshot Tests 8. Request-local edits do not mutate the source BandEvent | Yes |
| `find_musician_03a_test.dart` | FIND-MUSICIAN-03A.1 Entry Context & Request Snapshot Tests 9. Dismissing after editing performs zero event writes | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 1. A single event does not display EVENT 1 | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 10. Clicking Favorites List opens the complete existing list | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 11. No search field appears inside the existing Favorites List | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 12. The Favorites List heading uses the corrected presentation | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 13. Selection controls appear before musician names | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 14-17. Selecting a favorite collapses list, allows one choice, and displays Chosen Substitute | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 18. Reopening the list preserves the selected state | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 19. Selecting another Favorite replaces the previous choice | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 2. Adding Event 2 causes both Event 1 and Event 2 headings to appear | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 20. Clearing the choice hides Chosen Substitute | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 21. Slot 1 and Slot 2 maintain independent chosen Favorites | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 22-24. Favorite selection does not set assignedUserId, status, or display Assigned substitute | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 25. + Add Favorite(s) appears below Favorites List | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 26-31. Global + Add Favorite(s) search, persist via canonical API, prevent duplicates, and do not auto-choose | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 3. Multiple-event headings use the exact format: EVENT 2 - REHEARSAL: "Andra rep. Sommarturné" | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 32-33. Existing profile-star favorites and newly added favorites share canonical storage | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 34. New Member mode source controls: Favorites List on left, Search All on right | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 35-36. New Member mode opens favorites list and allows selecting favorites | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 37. New Member mode + Add Favorite(s) shares global implementation | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 38. Switching modes does not duplicate the Favorites panel | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 39. Existing New Member publication remains functional | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 4. No · separator remains in these headings | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 40. Existing request publication remains functional with chosen favorite | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 41. Secure assignment and Revoke remain unchanged | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 42. Existing 320 px layout renders without overflow | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 43. Create Event remains unaffected (snapshot isolation preserved) | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 44. Draft badge is completely absent for 1 slot, 2 slots, and multiple events | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 45. Complete 13-step asynchronous Favorites persistence, write verification, and write error rejection | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 46. Independent verification of Substitute and New Member Favorites workflows | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 47. Select All selects all saved Favorites without assigning and displays Chosen Substitutes | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 48. Paid Gig displays Details field, survives serialization, and reopens correctly | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 49. Find Gigs details view displays Description, Event name, and saved Paid Gig Details | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 5. One substitute slot does not display SUBSTITUTE 1 | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 50. Multi-event Find Gigs displays distinct Event name per occurrence without top-level collision | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 52. Numbered Substitute headings include straight-quoted event name with hyphen | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 53. Create Event supports attached sessions with + Add Session | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 6. Adding Substitute 2 causes both substitute numbers to appear | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 7. Removing Substitute 2 hides SUBSTITUTE 1 again | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 8. Substitute numbering is independent per event | Yes |
| `find_musician_03b_test.dart` | FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow 9. Favorites List appears left of Search All | Yes |
| `find_musician_04_test.dart` | FIND-MUSICIAN-UI-04: UI Corrections Widget Tests 10. Draft position shows "Remove Substitute" (not "Remove Slot") | Yes |
| `find_musician_04_test.dart` | FIND-MUSICIAN-UI-04: UI Corrections Widget Tests 11. Published position shows "Cancel Slot Request" (not Remove Substitute) | Yes |
| `find_musician_04_test.dart` | FIND-MUSICIAN-UI-04: UI Corrections Widget Tests 12. Paid Gig input formats with Swedish thousands separators | Yes |
| `find_musician_04_test.dart` | FIND-MUSICIAN-UI-04: UI Corrections Widget Tests 13. Publishing saves correct integer payAmount (1500) and payAmountMinor (150000) | Yes |
| `find_musician_04_test.dart` | FIND-MUSICIAN-UI-04: UI Corrections Widget Tests 14. New Band Member mode shares "Select All" and "+ Add Favorite(s)" layout | Yes |
| `find_musician_04_test.dart` | FIND-MUSICIAN-UI-04: UI Corrections Widget Tests 15. Responsive layout renders cleanly without errors or overflow | Yes |
| `find_musician_04_test.dart` | FIND-MUSICIAN-UI-04: UI Corrections Widget Tests 16. Favorites list filters out favorites who do not play the chosen instrument | Yes |
| `find_musician_04_test.dart` | FIND-MUSICIAN-UI-04: UI Corrections Widget Tests 17. Changing slot instrument dynamically filters the favorites list | Yes |
| `find_musician_04_test.dart` | FIND-MUSICIAN-UI-04: UI Corrections Widget Tests 18. Selecting an instrument with no matching favorites displays informative empty state and hides Select All | Yes |
| `find_musician_04_test.dart` | FIND-MUSICIAN-UI-04: UI Corrections Widget Tests 19. Changing instrument prunes non-matching favorite IDs | Yes |
| `find_musician_04_test.dart` | FIND-MUSICIAN-UI-04: UI Corrections Widget Tests 4. "Add all favorites" label is completely absent from the UI | Yes |
| `find_musician_04_test.dart` | FIND-MUSICIAN-UI-04: UI Corrections Widget Tests 5. "Select All" button is present and placed left-aligned directly above first favorite item | Yes |
| `find_musician_04_test.dart` | FIND-MUSICIAN-UI-04: UI Corrections Widget Tests 6. "Select All" is hidden when favorites list is empty | Yes |
| `find_musician_04_test.dart` | FIND-MUSICIAN-UI-04: UI Corrections Widget Tests 7. "Select All" selects all saved favorites without assigning a substitute | Yes |
| `find_musician_04_test.dart` | FIND-MUSICIAN-UI-04: UI Corrections Widget Tests 8. "+ Add Favorite(s)" button is placed below the favorites list with adequate spacing | Yes |
| `find_musician_04_test.dart` | FIND-MUSICIAN-UI-04: UI Corrections Widget Tests 9. "+ Add Substitute" button label is exactly "+ Add Substitute" with no duplicate plus icon | Yes |
| `find_requests_01b_test.dart` | FIND-REQUESTS-01B: Specification Verification 1. Visible order of editable request fields matches 1 to 6 in Find Musician/Vocalist | Yes |
| `find_requests_01b_test.dart` | FIND-REQUESTS-01B: Specification Verification 10. Existing-event entry preserves eventId and bandId and does not mutate BandEvent | Yes |
| `find_requests_01b_test.dart` | FIND-REQUESTS-01B: Specification Verification 11. Find Gigs cards classify Substitute, New Member and Other correctly | Yes |
| `find_requests_01b_test.dart` | FIND-REQUESTS-01B: Specification Verification 12. Find Gigs details sheet uses the required visible order 1 to 6 | Yes |
| `find_requests_01b_test.dart` | FIND-REQUESTS-01B: Specification Verification 13. Details sheet never shows the event name as Event Type | Yes |
| `find_requests_01b_test.dart` | FIND-REQUESTS-01B: Specification Verification 14. Details sheet formats date & time without fabricating fallback hours | Yes |
| `find_requests_01b_test.dart` | FIND-REQUESTS-01B: Specification Verification 15. Multiple substitute slots can still be added/removed | Yes |
| `find_requests_01b_test.dart` | FIND-REQUESTS-01B: Specification Verification 16. Direct invitations remain classified correctly and are not duplicated | Yes |
| `find_requests_01b_test.dart` | FIND-REQUESTS-01B: Specification Verification 17. Paid requests show payment amount and Details; unpaid requests do not show payment UI | Yes |
| `find_requests_01b_test.dart` | FIND-REQUESTS-01B: Specification Verification 18. Responsive rendering at 320 px width succeeds without RenderFlex overflow | Yes |
| `find_requests_01b_test.dart` | FIND-REQUESTS-01B: Specification Verification 3. Event Type options use BandEvent.standardEventTypes | Yes |
| `find_requests_01b_test.dart` | FIND-REQUESTS-01B: Specification Verification 4. Request Type options are Substitute, New Member, Other | Yes |
| `find_requests_01b_test.dart` | FIND-REQUESTS-01B: Specification Verification 5. Publishing Substitute persists RequestType = Substitute | Yes |
| `find_requests_01b_test.dart` | FIND-REQUESTS-01B: Specification Verification 6. Publishing New Member persists RequestType = New Member | Yes |
| `find_requests_01b_test.dart` | FIND-REQUESTS-01B: Specification Verification 7. Publishing Other + DJ persists RequestType = Other and role/instrument DJ | Yes |
| `find_requests_01b_test.dart` | FIND-REQUESTS-01B: Specification Verification 8. Publishing Other + Sound Engineer / Producer behaves equivalently | Yes |
| `gen_01_selection_field_tap_test.dart` | GEN-01 Selection Field Tap Interaction & Accessibility Tests 2. EditProfileScreen: Secondary Skills opens picker | Yes |
| `gen_01_selection_field_tap_test.dart` | GEN-01 Selection Field Tap Interaction & Accessibility Tests 7. FindSubScreen: Instrument/Skills opens picker on tap | Yes |
| `gen_batch_ui_test.dart` | GEN-02, GEN-03, GEN-04, GEN-05 Batch Presentation Tests GEN-02 / GEN-03: Headings and selectors display canonical Genres/Band Types and SKILLS/TALENTS | Yes |
| `gen_batch_ui_test.dart` | GEN-02, GEN-03, GEN-04, GEN-05 Batch Presentation Tests GEN-02: Collabs screens use normalized Songwriters/Producers and Studios/Engineers without space-surrounded slashes | Yes |
| `gen_batch_ui_test.dart` | GEN-02, GEN-03, GEN-04, GEN-05 Batch Presentation Tests GEN-02: Legitimate ampersand values (e.g. R&B) and legacy stored data load safely without crashing | Yes |
| `gen_batch_ui_test.dart` | GEN-02, GEN-03, GEN-04, GEN-05 Batch Presentation Tests GEN-04: Parenthetical text (if any) and (City, Country) use normal font weight while main label is bold | Yes |
| `gen_batch_ui_test.dart` | GEN-02, GEN-03, GEN-04, GEN-05 Batch Presentation Tests GEN-05: EditProfileScreen enforces relative section order Skills/Talents < Genres/Band Types < Level | Yes |
| `gen_batch_ui_test.dart` | GEN-02, GEN-03, GEN-04, GEN-05 Batch Presentation Tests GEN-05: MusicianProfileScreen enforces relative section order PRIMARY SKILL/TALENT < Genres/Band Types < Level | Yes |
| `gen_batch_ui_test.dart` | GEN-02, GEN-03, GEN-04, GEN-05 Batch Presentation Tests GEN-05: ProfileTabScreen enforces relative section order PRIMARY SKILL/TALENT < Genres/Band Types < Level | Yes |
| `global_create_event_phase1_test.dart` | Global Create Event Entry Point - Phase 1 Verification Tests 12. Preserved Band Room Create Event entry point remains present | Yes |
| `global_create_event_phase1_test.dart` | Global Create Event Entry Point - Phase 1 Verification Tests 7. User with exactly 1 authorized band (Leader) opens CreateEventPage directly | Yes |
| `home_activity_badges_test.dart` | HOME-NAVIGATION-CLEARING-01: Home Action Navigation & Isolation 11. Find Gigs tap completes navigation, clears only find_gigs, removes red dot immediately | Yes |
| `home_activity_badges_test.dart` | HOME-NAVIGATION-CLEARING-01: Home Action Navigation & Isolation 12. Collabs tap completes navigation, clears only collabs, removes red dot immediately | Yes |
| `home_activity_badges_test.dart` | HOME-NAVIGATION-CLEARING-01: Home Action Navigation & Isolation 13. Find Musicians tap completes navigation, clears only find_musicians, removes red dot immediately | Yes |
| `home_activity_badges_test.dart` | HOME-NAVIGATION-CLEARING-01: Home Action Navigation & Isolation 14. Band Room tap with active band completes navigation, clears only band_room, removes red dot | Yes |
| `home_activity_badges_test.dart` | HOME-NAVIGATION-CLEARING-01: Home Action Navigation & Isolation 15. Band Room blocked when no active band: does not navigate and does NOT clear activity | Yes |
| `home_activity_badges_test.dart` | HOME-NAVIGATION-CLEARING-01: Home Action Navigation & Isolation 16. Band selector dismissed without picking a band: does NOT navigate and does NOT clear activity | Yes |
| `instruments_list_update_test.dart` | Master Instrument and Skills List Verification Tests EditProfileScreen picker opens and contains updated categories and items | Yes |
| `instruments_list_update_test.dart` | Master Instrument and Skills List Verification Tests FindSubScreen picker opens and displays updated master category structure | Yes |
| `map_view_feed_test.dart` | loading map_view_feed_test.dart | Yes |
| `marketplace_redesign_test.dart` | Marketplace Redesign - UI & Interaction Widget Tests 1. Both main entry cards are visible with correct titles & subtitles | Yes |
| `marketplace_redesign_test.dart` | Marketplace Redesign - UI & Interaction Widget Tests 16, 17 & 18. Create Listing displays correct subcategories, preselects intent/category, and validates | Yes |
| `marketplace_redesign_test.dart` | Marketplace Redesign - UI & Interaction Widget Tests 2 & 4. Tapping I'M LOOKING FOR opens correct modal with 8 exact options in required order | Yes |
| `marketplace_redesign_test.dart` | Marketplace Redesign - UI & Interaction Widget Tests 20. Keyboard activation and semantic accessibility work | Yes |
| `marketplace_redesign_test.dart` | Marketplace Redesign - UI & Interaction Widget Tests 21. Listing Detail and My Listings remain functional | Yes |
| `marketplace_redesign_test.dart` | Marketplace Redesign - UI & Interaction Widget Tests 22. MARKETPLACE-02: Action standardization & Create Listing form order | Yes |
| `marketplace_redesign_test.dart` | Marketplace Redesign - UI & Interaction Widget Tests 3 & 5. Tapping I'M OFFERING opens correct modal with 8 exact options in required order | Yes |
| `marketplace_redesign_test.dart` | Marketplace Redesign - UI & Interaction Widget Tests 6 & 7. Selecting an option updates selector, closes modal, and remains fully tappable | Yes |
| `marketplace_redesign_test.dart` | Marketplace Redesign - UI & Interaction Widget Tests 8. Filters combine correctly with free-text search | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 1. Existing single-substitute workflow still works in standalone mode | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 10. Missing-participant prepopulation does not create duplicates | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 11. A manually added position without a replaced member works | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 12. Candidates are grouped under the correct slot | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 13. Assigning one candidate fills only the intended slot | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 14. Assigning one slot leaves unrelated slots open | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 15. Partial progress survives reopening without data loss | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 16. Reopening does not overwrite existing assignments | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 2. A legacy single request displays as one slot | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 20. Cancelling one slot preserves other slots and the event | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 22. The overall selection/status count is correct | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 23. UI works at 320 px width without overflow | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 24. Empty Favorites state is handled gracefully without silent fallback | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 26. Existing Event RSVP behavior is unchanged | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 27. Existing Finalize Event & Lock RSVPs behavior is unchanged | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 28. RSVP Prepopulation Audit: YES never drafted, NO drafted, UNCERTAIN & NO ANSWER require confirmation | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 29. Gig/Event Details (Schedule, Location, Description) are fully interactive and editable | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 30. Declined candidate responses (value == false) are excluded from the assignable list | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 32. Partial agreement chat failure preserves canonical assignment and displays recoverable notice | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 33. Regression: Page title is exactly FIND MUSICIAN/VOCALIST | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 34. Regression: Request Type control is visible before interaction | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 35. Regression: Substitute mode opens the unified multi-slot workflow | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 36. Regression: New Band Member mode does not show event substitute slots | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 37. Regression: New Band Member mode does not write externalInvitees | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 38. Regression: New Band Member mode preserves its historical persisted role value (Role: New Member) | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 39. Regression: Legacy Substitute request resolves to Substitute mode | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 4. Several draft slots can exist in one unified workflow (conditional numbering) | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 40. Regression: Legacy New Member request resolves to New Band Member mode | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 41. Regression: Switching modes does not leak draft state between them | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 43. Regression: Mode controls and New Member UI fit at 320 px without overflow | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 5. Slot 1 can independently choose Favorites source | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 6. Slot 2 can independently choose Search All source | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 7. All draft slots publish from one event-level action | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 8. Reopening restores all slots | Yes |
| `multi_subs_01_test.dart` | MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow 9. Two identical instrument/role slots remain separate | Yes |
| `notification_center_test.dart` | Compact Notification Panel Integration Tests 5. SubRequest response notification sets AppState unreadSubResponses and shows badge on Find Musicians button | Yes |
| `notification_center_test.dart` | CustomTopBar Notification Bell & Badge Tests 2. Badge displays exact count for 1 to 99 | Yes |
| `oct_sprint_01_events_calendar_test.dart` | OCT-SPRINT-01: Event Calendar polish 1. Kalenderkortet visar inte Live/Gig eller annan eventtyp-badge | Yes |
| `oct_sprint_01_events_calendar_test.dart` | OCT-SPRINT-01: Event Calendar polish 10. Event Calendar fungerar vid 320 px bredd utan overflow | Yes |
| `oct_sprint_01_events_calendar_test.dart` | OCT-SPRINT-01: Event Calendar polish 2 & 3. Datumet visas högst upp på kort med bild och utan bild | Yes |
| `oct_sprint_01_events_calendar_test.dart` | OCT-SPRINT-01: Event Calendar polish 4. Eventtypen finns fortfarande kvar och visas på Event Details | Yes |
| `oct_sprint_01_events_calendar_test.dart` | OCT-SPRINT-01: Event Calendar polish 5 & 6. Upload from this device visas och ingen Choose from Gallery text kvarstår | Yes |
| `oct_sprint_01_events_calendar_test.dart` | OCT-SPRINT-01: Event Calendar polish 7 & 8. Edit-knapp visas för skapare men inte för andra användare | Yes |
| `oct_sprint_01_events_calendar_test.dart` | OCT-SPRINT-01: Event Calendar polish 9. Vanliga användare kan öppna och läsa eventet men inte se Edit-knappen | Yes |
| `oct_sprint_01_events_calendar_test.dart` | OCT-SPRINT-01: Events-listan förenkling 1 & 2. Bandnamn är visuellt överordnat och eventnamn visas inom raka citationstecken | Yes |
| `oct_sprint_01_events_calendar_test.dart` | OCT-SPRINT-01: Events-listan förenkling 10. Upcoming and Past navigation opens read-only results page | Yes |
| `oct_sprint_01_events_calendar_test.dart` | OCT-SPRINT-01: Events-listan förenkling 11. Events-listan fungerar vid 320 px bredd utan overflow | Yes |
| `oct_sprint_01_events_calendar_test.dart` | OCT-SPRINT-01: Events-listan förenkling 3. Part Event visas inte på listkorten och eventtyp visas separat | Yes |
| `oct_sprint_01_events_calendar_test.dart` | OCT-SPRINT-01: Events-listan förenkling 4 & 5. New Events saknar inline-RSVP kontroller och saknar svarssammanställning | Yes |
| `oct_sprint_01_events_calendar_test.dart` | OCT-SPRINT-01: Events-listan förenkling 6 & 7. New Event-kort är klickbart och öppnar EventDetailsPage med YOUR RESPONSE intakt | Yes |
| `oct_sprint_01_events_calendar_test.dart` | OCT-SPRINT-01: Events-listan förenkling 8 & 9. Past Events visar inga redigerbara RSVP-kontroller och behåller resultatsammanställning | Yes |
| `p2_tasks_ui_cleanup_test.dart` | P2 Tasks UI & Presentation Regression Tests COL-03: Favorites CheckboxListTile uses leading control affinity | Yes |
| `p2_tasks_ui_cleanup_test.dart` | P2 Tasks UI & Presentation Regression Tests COL-04: Collaboration area helper text is not italic | Yes |
| `p2_tasks_ui_cleanup_test.dart` | P2 Tasks UI & Presentation Regression Tests FIND-02: Find Musician screen displays Gig/Event Details consistently | Yes |
| `p2_tasks_ui_cleanup_test.dart` | P2 Tasks UI & Presentation Regression Tests GIG-03: Gigs list tab labels are Substitute Requests, New Member Requests, and Saved without false booked claim | Yes |
| `profile_details_feedback_test.dart` | PROFILES-01 — MusicianProfileScreen All fields are still showing even if empty with None specified fallback | Yes |
| `profile_details_feedback_test.dart` | PROFILES-01 — MusicianProfileScreen Collaborations displays None specified when collabBio is empty without fabricated copy | Yes |
| `profile_details_feedback_test.dart` | PROFILES-01 — MusicianProfileScreen Collaborations displays helper text and populated collabBio | Yes |
| `profile_details_feedback_test.dart` | PROFILES-01 — MusicianProfileScreen Displays PRIMARY SKILL/TALENT (singular) and not plural variant | Yes |
| `profile_details_feedback_test.dart` | PROFILES-01 — MusicianProfileScreen Section order is PRIMARY SKILL/TALENT, then SECONDARY Skills/Talents, then Genres/Band Types | Yes |
| `profile_details_feedback_test.dart` | PROFILES-01 — ProfileTabScreen Displays PRIMARY SKILL/TALENT, ordered Genres, and Collaborations helper with neutral fallback | Yes |
| `profile_details_feedback_test.dart` | PROFILES-01 — ProfileTabScreen MusicianProfileScreen does not duplicate genre pills inside header card | Yes |
| `profile_details_feedback_test.dart` | PROFILES-01 — ProfileTabScreen ProfileTabScreen displays all fields even if empty with None specified | Yes |
| `profile_social_links_test.dart` | Social links clickable in MusicianProfileScreen Clicking Spotify and YouTube launches normalized URLs | Yes |
| `profile_social_links_test.dart` | Social links clickable in ProfileTabScreen Clicking Spotify and YouTube in own profile launches URLs | Yes |
| `public_event_calendar_feedback_test.dart` | EVENT-CALENDAR-01 Owner Feedback Tests 1. Search field placeholder is exactly "Search events..." | Yes |
| `public_event_calendar_feedback_test.dart` | EVENT-CALENDAR-01 Owner Feedback Tests 10. Screen renders without overflow at 320px-wide viewport | Yes |
| `public_event_calendar_feedback_test.dart` | EVENT-CALENDAR-01 Owner Feedback Tests 11. Tap Search events opens sheet, dismiss allows text entry without loop | Yes |
| `public_event_calendar_feedback_test.dart` | EVENT-CALENDAR-01 Owner Feedback Tests 12. No duplicate horizontal category-options row exists on the calendar screen | Yes |
| `public_event_calendar_feedback_test.dart` | EVENT-CALENDAR-01 Owner Feedback Tests 13. Calendar view is constrained to a max-width on wide desktop screens | Yes |
| `public_event_calendar_feedback_test.dart` | EVENT-CALENDAR-01 Owner Feedback Tests 14. Event cards display edit pencil icon button and tapping it opens edit event form for creator | Yes |
| `public_event_calendar_feedback_test.dart` | EVENT-CALENDAR-01 Owner Feedback Tests 14b. Event cards do NOT display edit pencil icon button for non-creators or mock events | Yes |
| `public_event_calendar_feedback_test.dart` | EVENT-CALENDAR-01 Owner Feedback Tests 15. Event cards display clickable Read More button that opens PublicEventDetailsScreen | Yes |
| `public_event_calendar_feedback_test.dart` | EVENT-CALENDAR-01 Owner Feedback Tests 16. PublicEventDetailsScreen displays upright A4 poster with tap-to-zoom InteractiveViewer modal | Yes |
| `public_event_calendar_feedback_test.dart` | EVENT-CALENDAR-01 Owner Feedback Tests 17. CreatePublicEventScreen displays upright A4 poster preview and Fit options | Yes |
| `public_event_calendar_feedback_test.dart` | EVENT-CALENDAR-01 Owner Feedback Tests 2. Tapping Search field immediately opens category picker sheet | Yes |
| `public_event_calendar_feedback_test.dart` | EVENT-CALENDAR-01 Owner Feedback Tests 3. Category options include Live/Gigs, Sessions, Workshops, and NOT Open Sessions | Yes |
| `public_event_calendar_feedback_test.dart` | EVENT-CALENDAR-01 Owner Feedback Tests 4. Selecting a category filters the event list to matching event types | Yes |
| `public_event_calendar_feedback_test.dart` | EVENT-CALENDAR-01 Owner Feedback Tests 5. Clearing category restores all events | Yes |
| `public_event_calendar_feedback_test.dart` | EVENT-CALENDAR-01 Owner Feedback Tests 6. Text search works alongside and after category selection | Yes |
| `public_event_calendar_feedback_test.dart` | EVENT-CALENDAR-01 Owner Feedback Tests 7. Venue and time row uses readable non-muted colors | Yes |
| `public_event_calendar_feedback_test.dart` | EVENT-CALENDAR-01 Owner Feedback Tests 8. Cards with images render with upright A4 poster proportions (portrait format) beside event text and BoxFit.cover | Yes |
| `public_event_calendar_feedback_test.dart` | EVENT-CALENDAR-01 Owner Feedback Tests 9. Cards without images render cleanly without broken or empty image box | Yes |
| `public_event_calendar_screen_test.dart` | PublicEventCalendarScreen Widget Tests 1. Renders title, subtitle and DEMO EVENTS badge | Yes |
| `public_event_calendar_screen_test.dart` | PublicEventCalendarScreen Widget Tests 10. Clear filters restores results and resets pagination | Yes |
| `public_event_calendar_screen_test.dart` | PublicEventCalendarScreen Widget Tests 11. Month headings are rendered once per visible month | Yes |
| `public_event_calendar_screen_test.dart` | PublicEventCalendarScreen Widget Tests 12. Empty repository shows No public events available yet. | Yes |
| `public_event_calendar_screen_test.dart` | PublicEventCalendarScreen Widget Tests 13. Failing repository shows error and retry button recovers when repository succeeds | Yes |
| `public_event_calendar_screen_test.dart` | PublicEventCalendarScreen Widget Tests 14. Pull-to-refresh re-fetches upcoming events | Yes |
| `public_event_calendar_screen_test.dart` | PublicEventCalendarScreen Widget Tests 15. Tapping event card navigates to PublicEventDetailsScreen with event argument | Yes |
| `public_event_calendar_screen_test.dart` | PublicEventCalendarScreen Widget Tests 16. Zero Firebase service calls made by public calendar | Yes |
| `public_event_calendar_screen_test.dart` | PublicEventCalendarScreen Widget Tests 2. Displays category picker with options and no duplicate chips row | Yes |
| `public_event_calendar_screen_test.dart` | PublicEventCalendarScreen Widget Tests 3. Initial pagination shows 2 events and Load More button | Yes |
| `public_event_calendar_screen_test.dart` | PublicEventCalendarScreen Widget Tests 4. Tapping Load More reveals 3rd event and hides Load More | Yes |
| `public_event_calendar_screen_test.dart` | PublicEventCalendarScreen Widget Tests 5. Filtering Live/Gigs shows only Stockholm Jazz Night without Load More | Yes |
| `public_event_calendar_screen_test.dart` | PublicEventCalendarScreen Widget Tests 6. Filtering Sessions shows only Open Co-writing Session without Load More | Yes |
| `public_event_calendar_screen_test.dart` | PublicEventCalendarScreen Widget Tests 7. Filtering Workshops shows only Music Production Workshop without Load More | Yes |
| `public_event_calendar_screen_test.dart` | PublicEventCalendarScreen Widget Tests 8. Search matches by title, organizer, venue, city, genre, and descriptions | Yes |
| `public_event_calendar_screen_test.dart` | PublicEventCalendarScreen Widget Tests 9. Combining search and type filters works correctly | Yes |
| `public_event_create_test.dart` | CreatePublicEventScreen Widget Tests Fills in form and successfully creates event | Yes |
| `public_event_create_test.dart` | CreatePublicEventScreen Widget Tests Renders Cover Image section and supports image URL | Yes |
| `public_event_create_test.dart` | CreatePublicEventScreen Widget Tests Renders form fields and validates required inputs | Yes |
| `public_event_create_test.dart` | PublicEventCalendarScreen Add Event Navigation Displays Add Event button in header and FloatingActionButton | Yes |
| `public_event_details_screen_test.dart` | PublicEventDetailsScreen & Integration Tests 1. Renders all details fields, genres, DEMO EVENT, and price correctly | Yes |
| `public_event_details_screen_test.dart` | PublicEventDetailsScreen & Integration Tests 2. Free event displays Free in price badge | Yes |
| `public_event_details_screen_test.dart` | PublicEventDetailsScreen & Integration Tests 2b. Event with imageUrl displays cover image widget | Yes |
| `public_event_details_screen_test.dart` | PublicEventDetailsScreen & Integration Tests 3. Invalid navigation argument gracefully displays fallback without crashing | Yes |
| `public_event_details_screen_test.dart` | PublicEventDetailsScreen & Integration Tests 4. Back to Calendar button pops details view | Yes |
| `public_event_details_screen_test.dart` | PublicEventDetailsScreen & Integration Tests 4b. Delete button shows confirmation dialog and Cancel retains view | Yes |
| `public_event_details_screen_test.dart` | PublicEventDetailsScreen & Integration Tests 4c. Confirming Delete calls repository.deleteEvent and pops view | Yes |
| `public_event_details_screen_test.dart` | PublicEventDetailsScreen & Integration Tests 4d. Tapping Edit opens CreatePublicEventScreen and updates event on save | Yes |
| `public_event_details_screen_test.dart` | PublicEventDetailsScreen & Integration Tests 5. Home View Event Calendar button navigates to /event-calendar | Yes |
| `registration_genres_test.dart` | Registration Genres/Band Types Verification Tests 5b. Reopening EditProfileScreen displays saved genres correctly | Yes |
| `rsvp_design_03_test.dart` | RSVP-DESIGN-03 Comprehensive Checklist Tests 10, 11, 12, 13. EventResultsPage standardized 5 pills, substitute pill, primary skill only, tap expansion | Yes |
| `rsvp_design_03_test.dart` | RSVP-DESIGN-03 Comprehensive Checklist Tests 14. Layout works at 320 px width without horizontal overflow | Yes |
| `rsvp_design_03_test.dart` | RSVP-DESIGN-03 Comprehensive Checklist Tests 16. EventResultsPage standalone Event Description card directly below Main Event Name, with empty fallback | Yes |
| `rsvp_design_03_test.dart` | RSVP-DESIGN-03 Comprehensive Checklist Tests 17. ManageEventsScreen displays upper Part Event badge and restricts edit action to Event Creator | Yes |
| `rsvp_design_03_test.dart` | RSVP-DESIGN-03 Comprehensive Checklist Tests 5 & 6. CreateEventPage attached items start from EVENT 1 and maximum 6 attached events | Yes |
| `rsvp_design_03_test.dart` | RSVP-DESIGN-03 Comprehensive Checklist Tests 8 & 9. Band Room Events tab displays exact headings and routes finalized/past to Results | Yes |
| `ruta_02_picker_hierarchy_test.dart` | RUTA-02B Structured Picker Widget Tests 23. EditProfileScreen uses the RUTA-02B redesigned hierarchy with standalone BANDLEADER | Yes |
| `ruta_02_picker_hierarchy_test.dart` | RUTA-02B Structured Picker Widget Tests 25. FindSubScreen uses the RUTA-02B centralized hierarchy | Yes |
| `simple_rsvp_02_test.dart` | SIMPLE-RSVP-02 Tests 2. CreateEventPage enforces max 6 events cap (1 main + 5 attached) | Yes |
| `simple_rsvp_02_test.dart` | SIMPLE-RSVP-02 Tests 4. EventDetailsPage displays all events answered confirmation banner | Yes |
| `skills_taxonomy_test.dart` | SkillsTaxonomy UI & Widget Consumer Tests 22. FindSubScreen opens instrument picker with master categories | Yes |
| `subrequest_hotfix_visibility_test.dart` | HOTFIX 2.78.6 — SubRequest Visibility & Management Gates 1. Manage Requests entry is visible in FindSubScreen even when active count is 0 | Yes |
| `subrequest_hotfix_visibility_test.dart` | HOTFIX 2.78.6 — SubRequest Visibility & Management Gates 15. 320 px layout has no overflow | Yes |
| `subrequest_hotfix_visibility_test.dart` | HOTFIX 2.78.6 — SubRequest Visibility & Management Gates 2. Entry opens existing management screen (SubRequestResponsesScreen) | Yes |
| `subrequest_hotfix_visibility_test.dart` | HOTFIX 2.78.6 — SubRequest Visibility & Management Gates 3. Creator feed request is displayed in creator management screen | Yes |
| `subrequest_hotfix_visibility_test.dart` | HOTFIX 2.78.6 — SubRequest Visibility & Management Gates 4. Other creator’s private request is not displayed | Yes |
| `subrequest_hotfix_visibility_test.dart` | HOTFIX 2.78.6 — SubRequest Visibility & Management Gates 7. Missing coordinates block submission with clear validation | Yes |
| `today_features_test.dart` | Today Features Tests 1. FindGigsScreen displays 4 tabs including "Applied" | Yes |
| `today_features_test.dart` | Today Features Tests 2. FindGigsScreen displays Sub and New Member tags on gig cards | Yes |
| `today_features_test.dart` | Today Features Tests 3. CreateBandScreen displays Band Members section with Leader and Add Member button | Yes |
| `today_features_test.dart` | Today Features Tests 4. ManageEventsScreen does not display inline RSVP buttons on New Events and card is clickable | Yes |

### Exact final file and Git state

Branch: `main`. HEAD: `ef78005a125bcef55ee29e4e8337f304e9435181`. Version: `2.79.3+252`. **33 changed/untracked files. Staging empty.** Working tree intentionally dirty; all task changes remain local and uncommitted.

Exact `git status --short` (also the exact changed/untracked file inventory):

```text
 M database.rules.json
 M database.transitional.rules.json
 M firebase_functions/index.js
 M firebase_functions/membership_authority.js
 M firebase_functions/package.json
 M firebase_functions/test/emulator_callables.test.js
 M firebase_functions/test/emulator_clean_schema_privacy.test.js
 M firebase_functions/test/emulator_map_pin_security.test.js
 M firebase_functions/test/emulator_rules.test.js
 M lib/providers/app_state.dart
 M lib/services/firebase_service.dart
 M lib/views/band_room_chat_screen.dart
 M lib/views/find_gigs_screen.dart
 M lib/views/find_sub_screen.dart
 M lib/views/home_screen.dart
 M lib/views/login_screen.dart
 M lib/views/notification_center_screen.dart
 M lib/views/sub_request_response_details_screen.dart
 M lib/views/sub_request_responses_screen.dart
 M lib/widgets/map_pin_details_card.dart
 M test/agreement_integrity_01_test.dart
 M test/find_sub_routing_and_banner_test.dart
 M test/manage_requests_lifecycle_01_test.dart
 M test/map_view_apply_test.dart
 M test/request_cards_01_test.dart
 M test/sub_request_self_response_test.dart
 M test/subrequest_data_consistency_01_test.dart
?? docs/auth_feedback_and_manage_guard_01.md
?? firebase_functions/test/emulator_auth_manage_guard.test.js
?? lib/models/request_management_access.dart
?? lib/utils/login_feedback.dart
?? lib/widgets/request_management_gate.dart
?? test/auth_feedback_and_manage_guard_01_test.dart
```

The Map page, feed, audio, location and navigation production files are unchanged. The existing staffing-only action in `map_pin_details_card.dart` gained an authorization wrapper; ordinary Map pin UI is unchanged. Map callable differences are authorization-only. No canonical/legacy fallback or duplicate protected write was added by the management guards.

No commit, amend, push, merge, deployment, production access, production reset/deletion/cleanup, migration, backfill, API enablement, production secret operation or version bump occurred. The separately authorized empty-data cutover remains pending. The 333 remaining baseline Flutter failures and notification timing sensitivity remain release gates. This is readiness for local review only, not release authorization.
