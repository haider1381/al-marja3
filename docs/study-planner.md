# Study planner

The Study Schedule page now lets each signed-in student choose Medicine, Surgery, Paediatric (`Pediatrics` in storage), or OB/GYN, then a chapter. It lists every matching library record, with source/type to distinguish similar titles, plus personally added titles. It does not invent a medical syllabus. At release the library has 30 records: Cardiology 13, Respiratory 14, Neurology 3, all Medicine. Chapters without content show an empty state and support custom titles.

A chapter plan stores a start date and planned calendar days. Each topic has its own completion checkbox. Chapter progress is completed topics / listed topics, including personal and retained snapshot titles. A removed library lecture keeps its snapshot title and completion (`lecture_id` becomes null). Session completion is independent of lecture completion; group progress measures completed study minutes and excludes breaks.

## Time planning

Students choose a title, chapter/lecture, total minutes or hours, focus-only or elapsed time, work/break minutes, start date/time, a horizon in days or weeks, allowed weekdays, and daily available minutes including breaks. Sessions fill permitted days from the daily start time. This is a scheduling planner, not a live countdown timer.

- 2 hours of focus, 30-minute sessions, 5-minute breaks: 4 study periods + 3 breaks = 135 elapsed minutes.
- 2 hours including breaks with those settings: 105 study minutes + 15 break minutes = 120 minutes.
- Breaks occur only between two study periods on the same day. No break follows the last session or crosses overnight. A final study period may be shorter. An elapsed remainder too short to fit another break is explicitly reported as unused.
- A week is 7 calendar days from the selected start date. If the selected horizon/weekdays/daily capacity cannot accommodate the target, preview fails with instructions rather than silently extending it.
- Limits: 365 calendar days, 43,200 target minutes, work 1–240 minutes, break 0–120 minutes, max 400 blocks. A daily window cannot extend past midnight. Dates use UTC arithmetic for calendar calculations, independent of DST; the date default uses the student's local calendar and times are user-entered local wall-clock values.

Preview does not save. Save uses a generated group UUID retained for retries. A successful save clears preview to prevent accidental resubmission. The RPC atomically inserts the group and all blocks; retrying the same UUID/config returns the existing group. A deliberately new preview permits a second distinct plan.

## Database and privacy

`supabase/study-planner.sql` documents the additive setup applied on 2026-10-03 (run once; it is not a repeatable bootstrap). A protected snapshot was created first at `setup_backup.study_schedule_before_planner_20261003`; the prior table had 0 records. Existing tasks and existing policies were retained. No lecture, file, authentication provider, editor permission, or AI backend was changed.

New tables: `study_chapter_plans`, `study_plan_topics`, `study_session_groups`. Existing `study_schedule` gains optional group/order/kind/minutes/date columns. Free tasks continue in the expandable weekly section. Sharing remains opt-in through the existing share page, includes dates/durations for generated periods, and retains name/notes/completed filters.

All new tables enforce own-user RLS for SELECT/INSERT/UPDATE/DELETE; anonymous access has no grants. Composite parent/owner foreign keys prevent attaching topics/groups/sessions to another user's plan. `save_study_session_group` is SECURITY INVOKER, empty search path, authenticated EXECUTE only; owner comes from `auth.uid()`, never from submitted user_id. Group deletion cascades only its scheduled blocks, preserving topic completion and unrelated free tasks. Parent/owner and user/lecture foreign keys have covering indexes. The backup is deliberately deny-all to browser roles (advisor's no-policy INFO is expected).

Loading and asynchronous responses are scoped to the active account. Account changes clear planner state. Failed checkbox updates restore saved state and show an error rather than pretending persistence.

## Validation

Run `node tests/study-plan-engine.test.cjs` from the repository root. The test extracts the pure scheduling engine from index.html using STUDY_ENGINE markers and checks totals, final fragments, zero rest, selected weekdays across days/weeks, insufficient capacity, invalid input, block cap, and 624 parameterized cases.

Browser verification used 390px phone, 768px tablet, 1440px desktop in light/dark themes, with a simulated Supabase adapter: progress persistence/reload, chapter dates, custom titles, preview/save, checkbox failures, session progress, account reset, empty chapters, no duplicate DOM IDs or horizontal overflow. Separate existing-site regressions covered navigation/profile, favorites/save errors, sharing/privacy, reader, settings, and AI panels. This did not use a student's authenticated browser session.

Real SQL tests under authenticated roles and two existing user IDs verified own CRUD, cross-user read/update denial, forged-owner insertion denial, cross-user parent FK rejection, idempotent retry, invalid-child atomic rollback, and group-only deletion. All synthetic test writes were rolled back. Database advisors introduced no new security WARN/ERROR; existing warnings about permission RPCs and password protection were not altered.
