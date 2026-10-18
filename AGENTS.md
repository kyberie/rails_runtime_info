# Agent instructions

## Purpose

`rails_runtime_info` is an internal, on-demand, read-only diagnostic Rack
endpoint. The owner prioritizes non-interference with existing applications
above additional diagnostic coverage. Integration is Gemfile + one explicit
route. The output is for troubleshooting humans; a fixed JSON schema is not
required.

## Non-negotiable runtime constraints

- Target Ruby 2.4+ and Rails 5.1+; optional APIs must be guarded. Do not introduce
  Ruby 2.5+ conveniences or syntax without a deliberate compatibility decision.
- No Railtie, Engine, middleware, initializer, route registration, hooks,
  instrumentation, monkey patches, persistent counters, caches or threads.
- Requiring the gem must define code only, load only its own implementation,
  and not boot Rails, read diagnostics, activate optional frameworks or connect
  anywhere. Request-time standard-library requires are allowed.
- No database/pool access, network connections, subprocesses, Gemfile/gemspec
  evaluation, Bundler resolution, Rails::Info, Rails.application lazy creation,
  queue-adapter construction or autoloading of optional framework constants.
- No forced GC, compaction, GC tuning, YJIT enable/reset/statistics toggles,
  ObjectSpace traversal, signals, asynchronous timeouts or worker termination.
- All request headers and ENV values are intentionally unredacted. Do not add
  filtering, credential heuristics or built-in authentication without approval.
  Authentication and access restrictions are the ingress operator's job.
- Return at most 100 KiB of request-body bytes; read at most one extra byte for
  truncation detection. Prefer a bounded prefix of existing RAW_POST_DATA without
  reading input again. Do not duplicate body caches through the Rack environment.
  Never rewind, drain, close or parse `rack.input`.
- Unknown application objects must remain opaque. Do not invoke arbitrary
  inspect/to_s/to_h/as_json/to_json methods or traverse lazy container subclasses.
- Each collector must fail independently. Ordinary failures belong in `errors`;
  fatal exceptions must propagate. Never log request data or errors globally.
- Keep request and snapshot data short-lived. The response body retains only
  serialized JSON and releases it on close. Do not retain request objects in
  closures, class/module variables, thread locals or global error stores.

"Read-only" means no intentional application mutation, not zero allocation,
zero observer overhead, or a guarantee that RSS falls after a request. Preserve
this distinction in documentation.

## Development workflow

Run standalone tests from the repository root:

```sh
ruby script/test
```

Build locally when needed:

```sh
gem build rails_runtime_info.gemspec
```

Do not install dependencies, fetch network resources, boot applications, run
Rails tests, contact services or publish artifacts without explicit permission.
The default tests run without Rails, Rack or Bundler. `script/rack_lint` is an
optional check using an already-installed Rack. Never treat synthetic Rails
objects as proof of full Rails integration compatibility.

Add focused regression tests for behavior changes. Test absent APIs, nil and
non-finite statistics, invalid strings, body boundaries, collector failures,
lazy objects, lack of persistent request retention and normal concurrent use.
Do not add live diagnostic output or real secrets to fixtures. Keep commands
on one physical line; longer Ruby source files may use normal multiline style.

Update README and docs/VALIDATION.md when behavior or tested environments
change. Clearly separate supported targets from actually executed tests. Do
not claim Ruby/Rails version coverage that was not run.

## Repository and publication

Preserve the private-publication safeguard and unselected license unless the
owner explicitly decides otherwise. Do not invent a remote repository URL.
Use this commit identity, configured locally before commits:

```sh
git config user.email git.codex.91ndg9n33q@hodor.cz
```

```sh
git config user.name 'Jan Seda'
```

When asked for a full bundle, commit intended files, include all refs/history,
verify it, and restore it into an empty location. A bundle is not a working-tree
archive and does not contain uncommitted files or local Git configuration.
