#+TITLE: Ocawe Code Review — Problems
#+DATE: 2026-02-23

Scope: src/framework, src/cli (~25k lines Crystal). Problems only — bugs,
security holes, correctness issues. No style or optimization notes.
Every finding was verified against source.

* Critical

** Silent data-wipe paths in persistence stores
- =src/framework/dataset/store.cr:252-261= — =snapshot()= rescues *all*
  exceptions and returns an empty =Snapshot=. The next mutating call then
  =persist()=s that empty state over =datasets.json=: one transient read/parse
  error permanently wipes the whole dataset store.
- Same pattern in =src/framework/secrets/store.cr:220-228= — =read_records=
  rescues-all and returns =[]=. =put= (=:28-43=) writes back an array holding
  only the new record: corrupt/unreadable =secrets.json= destroys *all stored
  secrets* on next write.
- Both stores write with plain =File.write= to the final path (no temp-file +
  rename). A crash mid-write truncates the file, which the rescue-all read path
  then converts into the full wipe above.

** Unauthenticated result endpoint
- =src/framework/http/endpoints/compat.cr:106-121= — =GET
  /v1/chat/completions/tasks/:taskId= has no =ensure_client_api_key!= check,
  while =POST /v1/chat/completions/tasks= (=:79=) requires one. Anyone who
  learns a task id reads the full request and completion payload. Task ids are
  =Random::Secure.hex(12)=, which mitigates enumeration but not leakage via
  logs/URLs/referrers.

** Spawned runtimes listen on all interfaces without auth
- =src/framework/workflows/declarative/exec_executor.cr:196-226= —
  =run_remote_caw_binary= spawns =ocawecore --port=<20000..40000>=. Kemal's
  default bind is =0.0.0.0= (=http/app/endpoints/base.cr:129= passes no host),
  so during execution the runtime exposes unauthenticated workflow-run HTTP on
  every interface, not just =127.0.0.1= where the parent connects.

** SSH host-key verification disabled for remote builds
- =src/cli/remote_builder.cr:198= — =ssh -o StrictHostKeyChecking=no ... =
  accepts any host key: build artifacts and deploy steps can be MITM'd between
  CI machine and builder.

* High

** Non-atomic multi-row / multi-statement writes
- =src/framework/dataset/store.cr:316-320= — =delete_dataset= runs two
  independent autocommit =DELETE=s; failure between them leaves datasets gone
  but items orphaned.
- =src/framework/dataset/store.cr:338-350= — =add_items= inserts per row
  without a transaction; mid-batch failure commits a partial batch yet raises,
  so callers cannot distinguish partial success.
- =src/framework/secrets/store.cr:28-43,85-89= — =put=/=delete= are unlocked
  read-modify-write rewrites of the whole JSON file: concurrent calls lose
  writes (last-write-wins).

** SQLite foreign keys effectively off
- =src/framework/dataset/store.cr:401= — =PRAGMA foreign_keys = ON= is
  per-connection in SQLite but is executed once on whichever pooled connection
  happens to run =migrate!=. Every other pooled connection runs with FKs off,
  so the =ON DELETE CASCADE= at =:420= is unreliable; integrity currently rests
  on the non-transactional manual delete above.

** False-success writes
- =src/framework/dataset/store.cr:354-376= — =update_item= is check-then-act:
  existence =SELECT= and =UPDATE= are separate statements and =rows_affected=
  is never checked. A concurrent delete between them yields "success" for a
  write that never landed.

** Upstream provider bodies leaked to clients
- =src/framework/providers/chat_completions_provider.cr:59= — errors embed the
  full upstream response body (=raise "... #{response.body}"=).
- =src/framework/http/endpoints/compat.cr:355-365= — endpoint error handlers
  pass =ex.message= straight into JSON error responses, so upstream account /
  gateway details reach API callers.

** Remote code execution by design, unpinned
- =src/framework/discovery/git_https_puller.cr:97-132= — clones arbitrary
  user-supplied refs (any host for git+ssh/git+https) and
  =exec_executor.cr:71-76= then runs workflows from the clone. No host
  allowlist, no ref/commit pinning requirement: any workflow node can pull and
  execute attacker-chosen code if input reaches =runtime.git+https=.

* Medium

** Process handling
- =src/framework/workflows/declarative/exec_executor.cr:229-234= —
  =terminate_process= sends SIGTERM then =wait= with no timeout; a child that
  ignores SIGTERM hangs the workflow fiber forever.
- =src/framework/workflows/declarative/exec_executor.cr:197= — port chosen as
  =20000 + Random.rand(20000)= with no collision retry; two concurrent remote
  execs can fail on bind.

** Multi-process file stores lose updates
- =src/framework/dataset/store.cr:152,158-261= — the =File= store's =Mutex= is
  per-process only while the backend is a shared file; two processes sharing
  =file_root= interleave full-file rewrites and silently drop each other's
  writes.

** DSN construction
- =src/framework/dataset/store.cr:274= — filesystem path interpolated raw into
  =sqlite3://#{@path}=; paths containing =?=, =#=, or whitespace misparse the
  URI (wrong DB file or driver options). Config-sourced, low likelihood, real
  consequence.

* Low / hygiene

- =tmp-executor-entry.cr= sits untracked at repo root — scratch code that will
  confuse the next reader; move under spec/ or delete.
- =chat_completions_provider.cr:18= checks =COGNICORE_MOCK_LLM= — legacy
  project name in env var; the mock toggle is undiscoverable under ocawe naming.
- =client_api_keys.cr:22-27= — =admin_key= falls back to scanning all of =ENV=
  for any =*_ADMIN_KEY= suffix; unrelated services' admin keys on the same host
  silently become ocawe admin keys.
- Federation pollers log via =STDERR.puts=
  (=federation_aptok_subscriptions.cr:118,133=) instead of the tracing logger —
  invisible to structured telemetry.
- =chat_completion_tasks= dataset grows unbounded; completed tasks are never
  pruned.
