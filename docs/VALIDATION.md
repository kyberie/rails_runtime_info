# Validation record

## Version 0.2.1 - executed on 2026-10-18

Environment: Linux x86_64, MRI Ruby 3.3.8, Minitest 5.20.0, JSON 2.7.2,
RubyGems 3.6.7 and Bundler 2.5.22. No Rails installation or application was used.

The standalone suite passed with **120 tests, 516 assertions, zero failures,
zero errors and zero skips**. The final suite was run with seeds 24680 and
43210. Tests require neither Rails nor Rack nor Bundler.

```sh
ruby script/test
```

Changes covered by regression tests include:

- Only activated gems are collected. There is no lockfile parser or inventory;
  a gems-only request succeeds with file opens disabled and a nonexistent
  BUNDLE_GEMFILE.
- The exact default selection and JSON ordering; bare and signed rules, parent
  resets, nested inclusions/exclusions, all/none, repeated query parameters,
  plain URLs, legacy encoded and literal plus signs, encoded comma/key names,
  invalid selectors and parser size/depth/rule limits.
- An independent last-matching-rule reference agrees with the selection tree
  on 100 deterministic randomized sequences of 16 rules each, mixing bare,
  plus-prefixed and minus-prefixed rules.
- Unselected collectors do not run. The default excludes request.body and does
  not invoke its collector, even for cached bodies. Known cached-body entries
  remain descriptors rather than payloads. Explicit request.body, request and
  all selections restore bounded capture; a later body exclusion prevents it.
  Disabling request.rack_environment skips its normalization. Invalid selection
  returns 400 before collection/body reads.
- The six-key Action Dispatch allowlist; omitted secret_key_base, legacy
  secret_token, key-generator/rotation data, unknown future keys and
  rack.session.options; recursive aliases/symbol keys; selectors cannot restore
  omissions; input hashes are unchanged. Only synthetic secrets are fixtures.
- HTTP credentials and explicitly selected environment values remain visible,
  as required. This is intentionally not universal secret redaction.

Previously established coverage remains for request metadata, UTF-8/binary
strings, body boundaries and cached bodies, short reads and consumed streams,
cycle/depth/node guards, opaque lazy objects, optional framework constants,
full GC/YJIT hashes, nil/NaN statistics, collector isolation, error-message and
JSON fallbacks, fatal exceptions, HEAD, concurrent requests and body closure.

Additional executed checks:

- A fresh Ruby subprocess verifies that requiring the gem loads only its own
  files and does not activate other gems, alter ENV/load paths, create threads,
  or load Rails.
- A WeakRef test verifies that a completed response does not retain its request
  environment. Forced GC is used only in tests, never by library code.
- Real Linux /proc reads exercise memory/status, process lifetime and FDs;
  failures and unusual process names are covered with test doubles.
- Syntax checks pass for every Ruby library/test file, the gemspec, Rakefile
  and scripts under Ruby 3.3.8. This is not a Ruby 2.4 parser check.
- `gem build` succeeds; the sole warning is the deliberately unspecified
  homepage. The packaged library is loaded and exercised from an isolated
  extraction in a fresh subprocess, with no dependency installation.
- `ruby script/bundler_smoke` passes using installed Bundler 2.5.22 for both
  automatic Bundler.require loading and explicit require with require: false.
  Each uses its own temporary path-only Gemfile. Bundler performs its normal
  local setup and may create a temporary lockfile; the endpoint never reads
  it. There is no Rails boot, remote source or dependency installation.
  Bundler warns that these deliberately local-only Gemfiles have no global
  source; no remote source is added merely to silence that warning.
- `git diff --check` passes.

## Explicitly not executed

**Actual Rails integration and Ruby 2.4/2.5 execution have not been tested.**
Ruby 2.4+ and Rails 5.1+ remain implementation targets, not verified version
coverage. Synthetic Rails configuration objects do not substitute for real
applications. Rails/Rack source inspection supports the omission policy, but
is not an integration test.

`script/rack_lint` reports Rack unavailable and exits 2. No actual Rack 2/3
lint run is claimed. No packages were installed to add those environments.

No real Passenger/Puma server, enabled YJIT instance, non-Linux host, ingress
Basic authentication configuration or deployed Rails middleware chain was
exercised. No database or external-service checks were performed.

## Deployment acceptance checks still needed

In an authorized test environment, add the documented explicit require and
route, then make an authenticated request through the actual proxy/application
stack. Confirm default output without body capture, plain `what` selections,
explicit bounded body capture, request ID visibility, absence of the forbidden
framework keys and a normal
application request. Verify alternate ingress/backend paths cannot reach the
endpoint without protection. Confirm proxy body/time limits are appropriate.

Do not commit live output: HTTP credentials and explicitly requested ENV still
contain secrets. Test older runtimes and Rails versions before declaring their
compatibility verified. This record is bounded evidence, not a guarantee
against arbitrary application monkey patches, middleware, OS failures or
resource exhaustion.

Earlier validation records are preserved in Git history and tags v0.1.0 and
v0.2.0. The new runtime behavior is confined to the selector parser/defaults;
other collectors and permanent omission rules are unchanged.
