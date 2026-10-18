# rails_runtime_info

A small, on-demand diagnostic Rack endpoint for Rails applications. Add the gem
and one route; inspect a pretty-printed JSON snapshot when troubleshooting.

**This endpoint deliberately returns credentials present in the request and
process environment. It has no authentication or redaction. Protect it at a
trusted ingress with Basic authentication over TLS and appropriate network
restrictions before enabling the route.**

## Motivation and constraints

The intended use is occasional, internal troubleshooting across several Rails
applications: which Ruby, gems, deployment and worker are actually running;
what the proxy sent; how GC, YJIT and process memory look at that moment.

This is a non-invasive, best-effort, **read-only observer**, not a health check,
profiler, management interface, dependency checker or application controller.
The gem must not initialize services or change how ordinary application
requests execute. It must remain useful when an optional collector fails.

Requiring it defines the implementation only. There is no Railtie, engine,
middleware, initializer, Passenger hook, background thread, instrumentation,
monkey patch or automatic route registration. There are no declared runtime gem
dependencies; JSON and small standard-library facilities are loaded only when
needed for a diagnostic request. Existing Rails/Rack/Bundler installations are
observed, not required or reconfigured.

## Install and route

Restore the repository from the supplied full Git bundle:

```sh
git clone rails_runtime_info.bundle rails_runtime_info
```

For an adjacent local checkout, add this to the application's Gemfile in a group
that is loaded in the environments where the endpoint is needed:

```ruby
gem "rails_runtime_info", path: "../rails_runtime_info"
```

For shared deployments, push the restored repository to your private Git host
and use the organization's normal pinned Git-gem dependency convention. There
is no assumed public RubyGems release. Alternatively, build the gem in this
repository and distribute it through your private gem repository:

```sh
gem build rails_runtime_info.gemspec
```

Add one line **inside the application's existing routes block**, before any
catch-all or controller-authentication constraint:

```ruby
match "/_internal/diagnostics", to: RailsRuntimeInfo::Endpoint, via: :all, format: false
```

`format: false` avoids the usual optional format suffix. Check that ingress
protection and Rails route matching cover the same paths, including any path
normalization, trailing slash or mount prefix accepted by the deployment.
Protecting the entire internal diagnostic namespace is safer than an exact
proxy match whose semantics differ from the router's.

The endpoint class does not choose a path; the route does. `via: :all` permits
request inspection with different HTTP methods. HEAD returns response headers
but no response body. There is no application-controller authentication, CSRF
handling or parameter parsing in this gem. Existing application middleware and
outer route constraints still apply and can reject or modify a request first.

Normal Bundler installation and application restart/deployment procedures still
apply. Removing the route and Gemfile entry removes the integration.

## Compatibility

The code targets **Ruby 2.4+ and Rails 5.1+**, without requiring Rails to use the
Rack callable. Optional methods and constants are checked before use. Linux
collectors are optional; a non-Linux application still gets the other sections.
There is no Passenger dependency. The response uses lowercase headers and does
not require a rewindable Rack input stream, accommodating Rack 2/3 conventions.

These are implementation targets, not a claim that every version combination
has been tested. See [validation](docs/VALIDATION.md) for exactly what was run.
The application itself must support its chosen Ruby/Rails/Rack combination.

## Collected information

| Section | Contents |
| --- | --- |
| `runtime` | Ruby description/version/engine/platform/executable, selected build information and versions of relevant activated libraries. |
| `application` | Already-instantiated Rails application identity, environment, root, initialization state, selected configuration, existing cache backend class and configured job-adapter value. Selected deployment environment variables are highlighted. |
| `gems.activated` | All entries from `Gem.loaded_specs`, with name, version and platform. Activated does not mean every library file has been required. |
| `gems.locked` | Gem names, versions and platform variants from the on-disk lockfile, across GEM/GIT/PATH/PLUGIN SOURCE sections. This is a locked inventory, not a newly resolved or active-platform-only bundle. |
| `environment` | Full `ENV`, with no filtering. |
| `loaded_features`, `load_path` | Copies of `$LOADED_FEATURES` and `$LOAD_PATH`. |
| `gc` | Complete results of available `GC.stat`, `GC.latest_gc_info` and `GC.stat_heap` calls. |
| `yjit` | Availability, enabled/statistics flags where supported and the complete available `runtime_stats` result, including `null` when returned by Ruby. |
| `process` | PID/PPID, user/group IDs, Ruby thread count, CPU time, working directory, program name, arguments and `Etc.uname`. No account-name or hostname lookup is performed. |
| `process.linux` | `/proc/self/status`, `smaps_rollup`, I/O counters, limits, cgroups, command line, executable link, FD count, estimated process lifetime, OS release and allocator-library hints. |
| `server` | Rack's server-software value and passive information from an already-loaded `PhusionPassenger` constant. This does not prove which server handled the request. |
| `request` | Method, URI fields, query string, scheme/protocol/address metadata, all available HTTP header values, reconstructed URL, safe Rack-environment snapshot and bounded raw body. |
| `errors` | Independently failed collectors, with exception class and best-effort message. |

No database collector is present, not even connection-pool inspection. There
are no SQL queries, database connections, Redis calls, job-adapter initialization,
network calls, external commands or application-health checks. There are no
custom collector callbacks in this version.

### Gems and lockfiles

`Gem.loaded_specs` is read without enumerating installed gem directories or
requiring the listed gems. The second inventory uses a deliberately small,
plain-text lockfile reader, **not** `Bundler.load`, `Bundler.definition` or
`Bundler::LockfileParser`. It never evaluates Gemfile/gemspec code or constructs
Bundler source objects.

`BUNDLE_GEMFILE` takes precedence. Its corresponding `.lock` file is used, with
`gems.rb` mapped to `gems.locked`. Otherwise, the existing Rails root is used,
or the current directory when Rails/root information is unavailable. In that
directory, an existing `gems.rb` selects `gems.locked`; otherwise `Gemfile.lock`
is selected. There is no parent-directory search. An unreadable, missing or
malformed lockfile is a local collector error, not a request failure.

The original `version_and_platform` string is retained alongside parsed version
and platform fields. Platform variants and inactive gems remain separate entries.
Unknown future lockfile sections are ignored; malformed entries inside a specs
section are reported. This is inventory extraction, not full Bundler validation.
An on-disk lockfile changed after worker startup can legitimately differ from
that worker's activated gems.

### Request fidelity and limits

HTTP header values, including Authorization, Cookie and custom credentials, are
not filtered. Header names in `request.headers` are reconstructed from Rack's
normalized names; original Rack keys remain in `request.rack_environment`.
Duplicate-header boundaries, original capitalization/order and exact wire bytes
already discarded by the server cannot be recovered. Forwarded headers are
reported as data, not trusted as authorization or independently interpreted.
`reconstructed_url` uses the Rack scheme, Host/server fields, script/path and
query; raw URI fields are reported separately when supplied by the server.

When an already-buffered Rails `RAW_POST_DATA` String exists, its bounded prefix
is used without copying the entire cache or touching `rack.input`. Known raw and
parsed body-cache entries in the Rack-environment snapshot are descriptors, not
duplicate payloads, so they cannot bypass this capture limit. These include
`RAW_POST_DATA`, Rack form caches and Rails request-parameter caches. Custom
middleware data under other keys is not inferred to be a body cache.

Otherwise the body reader reads **at most 102,401 bytes**, returns at most **102,400 bytes
(100 KiB)**, and uses the extra byte to detect truncation. It reads from the
stream's current position, handles short reads, and never rewinds, drains,
closes or parses `rack.input`. A stream consumed by earlier middleware cannot
necessarily be reconstructed when no raw body cache is available. Content-Length is reported but not trusted to
establish how many bytes were actually available.

Text is returned as UTF-8; binary/invalid-UTF-8 bodies use Base64, with explicit
encoding, source, byte counts and truncation fields. With a cached body,
`bytes_read` is zero and `cached_bytes` reports the original buffered size. Base64 and JSON overhead are not
part of the 100 KiB input-byte limit. A truncation inside a UTF-8 character uses
Base64 so no captured byte is silently discarded.

Other invalid-UTF-8 strings are represented by a tagged Base64 object rather
than lossy replacement. Non-finite floats such as NaN/Infinity are tagged rather
than causing JSON generation to fail. Integer/symbol object keys become JSON
strings where unambiguous; unsupported or colliding keys use a tagged entries
list. Cycles are marked. Application objects and Hash/Array subclasses are
opaque class descriptions, not `inspect`, `to_h`, `as_json` or `to_json` output;
this avoids materializing lazy sessions and other application state.

Defensive normalization is bounded to depth 24 and 100,000 nodes per normalized
field, with explicit limit markers. Ordinary header/environment string values
have no separate truncation limit. Known local files are bounded to 64 KiB,
allocator map scanning to 2 MiB, and the lockfile to 4 MiB. An oversized local
file is reported as unavailable, not silently parsed as a complete file.

### Failures and response lifetime

Ordinary collector failures, including unavailable optional libraries/APIs,
produce a partial **200** response with entries under `errors`. Missing optional
APIs may simply be omitted; YJIT unavailability is explicit. A collector returning
`null` is not reinterpreted as zero or disabled. Fields are a human-facing format,
not a versioned schema contract.

A last-resort ordinary snapshot/JSON failure produces a static JSON **500**
response. Error reporting does not invoke Rails logging. `NoMemoryError`,
`SystemExit`, `Interrupt` and other fatal/non-ordinary exceptions are not
swallowed. A killed, wedged or exhausted worker cannot be rescued by this gem.

Snapshots and normalizers are request-local. No full snapshot, environment,
request, exception object or response history is retained in module/class
state. The Rack response body holds only the final JSON string; `close` clears
that reference even if the response object remains reachable. Rack servers and
middleware must close it. The gem never calls `GC.start`, changes GC settings,
compacts the heap, or enables/resets YJIT/statistics. Reclaimable Ruby objects do
not imply immediate GC or a reduction in RSS.

## Meaning of "read-only"

The gem performs observation, not business operations or persistent application
configuration changes. It is not literally free of effects: Ruby files must be
loaded, some standard-library activation can persist after the first diagnostic
request, collection/serialization allocates objects and consumes CPU, files may
acquire access-time changes, and reading the request body advances its stream.
Normal allocations can trigger ordinary GC/JIT activity. Kernel accounting and
some runtime accessors also perform work. These are not hidden guarantees of
zero overhead or zero initialization inside Ruby itself.

All observations concern the **worker serving this request**, and collection is
not atomic. GC counters can include state inherited from a preloader. Linux
process age comes from the current process rather than gem load time, so no
fork callback is required. The estimated wall-clock start time is approximate.
FD counts include diagnostic activity; memory counters can change while read.
PSS/`smaps_rollup` can be unavailable on older kernels or under restrictions.
Allocator-library mappings are hints only, not proof of the allocator in use.
No processed-request counter is synthesized.

There are deliberately no asynchronous timeouts or worker-killing mechanisms.
A slow request-body stream or filesystem can still block. Set request-body size,
read-time and concurrency limits at the proxy/server. Use this endpoint
occasionally; it is not a high-frequency monitoring or liveness endpoint.

## Development and checks

Standalone tests require an installed, compatible Minitest, but neither Rails
nor Rack nor Bundler is necessary to run them:

```sh
ruby script/test
```

The development Gemfile pins test-tool ranges compatible with the Ruby 2.4
target. `script/test` also works with a suitable already-installed newer
Minitest on a newer Ruby. No dependency installation happens automatically.

An optional standalone Rack::Lint smoke script is provided for environments
where Rack is already installed. It does not boot Rails:

```sh
ruby script/rack_lint
```

A specific installed Rack version can be selected:

```sh
RACK_VERSION=2.2.9 ruby script/rack_lint
```

Read [AGENTS.md](AGENTS.md) before changes. See [design notes](docs/DESIGN.md) for
implementation boundaries and [validation](docs/VALIDATION.md) for known gaps.
Do not store live diagnostic output in this repository: it contains secrets.

## Distribution and license

No public distribution license has been selected; see [LICENSE](LICENSE).
The gemspec sets a deliberately non-routable `allowed_push_host` to help prevent
accidental publication. The owner must select an appropriate private registry
configuration or public license before publishing. No remote Git host is assumed.
A Git bundle carries commits/refs, not the source repository's local Git config.
