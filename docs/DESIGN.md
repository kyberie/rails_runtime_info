# Design notes

## Public surface

The only integration API is `RailsRuntimeInfo::Endpoint.call(env)`. It returns a
Rack status/header/body tuple. Route selection and authorization are entirely
outside the gem. The endpoint can also be called without Rails present.
`RailsRuntimeInfo::VERSION` identifies the implementation; JSON structure is
not promised stable.

## Implementation layout

| Component | Responsibility |
| --- | --- |
| `endpoint.rb` | Deferred JSON require, top-level ordinary-failure fallback, Rack headers and HEAD handling. |
| `body.rb` | Enumerable Rack body retaining only serialized JSON; idempotent release on close. |
| `snapshot.rb` | Request-local orchestration, per-field and per-section exception boundaries, framework/runtime observation. |
| `normalizer.rb` | Copies safe primitives, guards traversal, avoids application serialization hooks and represents unsupported/binary/non-finite data. |
| `request_info.rb` | Raw request metadata, reconstructed headers/URL and bounded body capture. |
| `linux_process.rb` | Bounded /proc readers and limited parsing; no subprocesses or native bindings. |
| `lockfile.rb` | Plain-text inventory extraction, without invoking Bundler or loading gems. |
| `support.rb` | Non-autoloading constant lookup, class labels, UTC formatting and bounded regular-file reads. |

Known Rack/Rails body caches are descriptors in the environment snapshot, not
second copies of an unbounded body. Existing RAW_POST_DATA is used only through
a bounded prefix. Other input streams are read at most 100 KiB plus one byte.

No request context reaches a class-level cache. `Snapshot` and its referenced
request become unreachable after serialization returns. `Body` stores no block,
normalizer, snapshot or request, and drops the JSON reference on `close`.

## Rails is optional, and initialization is deliberately avoided

Calling `Rails.application` can instantiate the application's singleton.
Calling `Rails.root`/`Rails.configuration` can reach that same path. To avoid
creating anything in an unusual partially initialized environment, the Rails
collector reads only an existing `Rails.@application`, its existing `@config`,
and the existing cached `Rails.@_env`. Absence is reported rather than forcing
initialization. These private storage details are a small, isolated compatibility
risk; a changed Rails implementation should result in less information, not
fallback to lazy creation. Access to selected configuration readers is guarded
and exception-isolated.

The existing cache object contributes its class name only. The job adapter is
read from configuration, never instantiated through ActiveJob. ActiveRecord is
not referenced by library code at all. Optional constants are not resolved when
they are registered as autoloads. Passenger contributes an existing version
constant only; there are no fork hooks or request counters.

## Error policy

Field captures include normalization inside their exception boundary. Section
assembly also has an ordinary-error boundary, so a future programming mistake
in one section should not suppress unrelated information. Successful sections
are not normalized a second time, avoiding a redundant large copy.

Handled optional failures are `StandardError`, `LoadError` and
`NotImplementedError`. The latter two are explicitly named because they are not
StandardError subclasses. Never rescue `Exception` wholesale. Exceptions and
backtraces are not stored; only class-name and normalized message data are
returned. Failure formatting has its own fallback.

The last-resort JSON response is a constant literal so a broken or missing JSON
serializer cannot recursively break its own error handler. It uses status 500.
A partial successful diagnostic snapshot uses 200, even when some collectors
failed. Neither path asserts application health.

## Serialization policy

Strings are copied into plain Strings. Valid UTF-8 bytes are returned as text;
otherwise a Base64 descriptor preserves the original bytes and encoding label.
Opaque objects are represented by a class-name descriptor. Hash and Array
subclasses are not traversed because their methods can perform lazy work.
Ordinary Hash/Array cycles, depth and traversal limits are represented explicitly.

Standard symbol/integer keys become JSON keys. Binary keys, non-primitive keys
and key collisions become a tagged entries list, not silently overwritten data.
NaN/Infinity retain their meanings in tagged objects rather than being emitted
as non-standard JSON tokens or replaced with zero/null.

The complete available GC/YJIT hashes are retained subject to the same defensive
normalization bounds. Counters are not assumed to have the same names across
Ruby releases, and missing counters never imply a negative result. No attempt
is made to infer a `yjit_used` boolean from an absent counter.

## Operating-system observations

Known local files are opened read-only with a bounded read and closed using a
block. Nonblocking open plus fstat rejects FIFOs/devices/directories for these
readers. This does not provide a deadline for regular filesystem operations or
kernel-generated /proc data. Request input is also not subject to a Ruby-level
timeout; asynchronous exceptions would undermine the non-invasive constraint.

The lifetime calculation parses field 22 of `/proc/self/stat`, taking account
of spaces/parentheses in comm, obtains clock ticks via `Etc.sysconf`, and compares
with `/proc/uptime`. It reports an approximate wall-clock start time. It is
independent of preloader state and gem load time. No shell `getconf`, `ps`,
`passenger-status`, uname or allocator-native call is executed.

There is no full smaps fallback when smaps_rollup is unavailable. `/proc/self/maps`
is scanned only for allocator-library names; it is not returned wholesale and
cannot identify statically linked allocators or prove active allocation routing.

## Upstream references consulted

These references explain the underlying interfaces; they do not substitute for
running a compatibility matrix. The implementation is original and does not
vendor Rails, Rack, Bundler or Ruby sources.

- Rails 5.1 Rack routes: https://guides.rubyonrails.org/v5.1/routing.html#routing-to-rack-applications
- Rails 5.1.7 application/environment accessors: https://github.com/rails/rails/blob/v5.1.7/railties/lib/rails.rb
- Rack 3.2 specification: https://rack.github.io/rack/3.2/SPEC_rdoc.html
- Ruby 2.4 Etc: https://docs.ruby-lang.org/en/2.4.0/Etc.html
- Ruby YJIT observation APIs: https://docs.ruby-lang.org/en/3.3/RubyVM/YJIT.html
- Linux proc documentation: https://docs.kernel.org/filesystems/proc.html
- Bundler lockfile naming conventions: https://github.com/rubygems/rubygems/blob/v3.5.22/bundler/lib/bundler/shared_helpers.rb
