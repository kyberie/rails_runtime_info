# Validation record

## Executed on 2026-10-18

Environment: Linux x86_64, MRI Ruby 3.3.8, Minitest 5.20.0, JSON 2.7.2 and
Bundler 2.5.22. No Rails or Rack installation was used by the default suite.

The final standalone suite passed with **79 tests, 239 assertions, zero
failures, zero errors and zero skips**, including repeated randomized execution
orders (seeds 43210 and 24680). Tests run without loading a Rails application.

```sh
ruby script/test
```

Coverage includes request headers/environment with credentials deliberately
visible, raw and reconstructed request metadata, UTF-8/binary data, exact body
limits, oversized/short-read/consumed streams, bounded Rails raw-body caches,
prevention of duplicate body-cache exposure, cycle/depth/node limits, inactive
and platform-specific locked gems, missing/malformed/oversized files, optional
framework constants/autoloads, isolated field/section errors, JSON fallback,
full GC/YJIT hashes, nil/NaN statistics, fatal-exception propagation, HEAD,
concurrent requests and response closure.

Additional executed checks:

- A fresh Ruby subprocess verified that requiring the gem loads only its own
  Ruby files, does not activate other gems, alter ENV/load paths, add threads,
  or load Rails.
- A WeakRef check verified that the Rack response does not keep its request
  environment alive. Forced GC is used only in that test, never by the library.
- Real Linux /proc reads exercised process lifetime, memory/status fields and
  FD counts; isolated failures and unusual comm strings used synthetic inputs.
- Ruby syntax checks passed for implementation, tests, gemspec, Rakefile and
  scripts under Ruby 3.3.8. This is not a Ruby 2.4 parser check.
- `gem build` succeeded. RubyGems warns about the intentionally unspecified
  homepage; no remote repository URL was invented.
- The built gem was installed into a separate local gem directory with no
  dependency installation. A fresh process required that installed copy,
  obtained a 200 JSON response, checked its byte length, and closed its body.
- An actual Bundler 2.5.22 setup with a temporary local path-gem Gemfile loaded
  the endpoint, returned 200, and reported the generated lockfile inventory.
  This was not a Rails test and did not involve a deployed application.

## Explicitly not executed

**Ruby 2.4/2.5 runtime tests and actual Rails integration tests have not been
run.** Ruby 2.4+ and Rails 5.1+ are implementation targets. Synthetic Rails
5.1-style configuration objects and optional-API guards are not a substitute
for testing real applications on those versions.

`script/rack_lint` was attempted and reported that Rack was not installed. It
therefore did not verify an actual Rack 2 or Rack 3 implementation. The supplied
script can perform that check where a compatible Rack is already available.
The default tests verify the response tuple/headers/body behavior directly.

No real Passenger/Puma server, active YJIT runtime, non-Linux host, ingress Basic
authentication configuration, Rails middleware chain or full deployment was
exercised. YJIT variants are covered by test doubles; this Ruby build does not
expose a YJIT module. No database or external-service checks were performed.

## Deployment acceptance checks still needed

In an authorized test environment, add the route and verify an authenticated
request through the actual proxy and application stack. Check a representative
ordinary application request as well. Confirm the endpoint is inaccessible
through alternate ingress paths and direct backend listeners, and that proxy
body/time limits are appropriate. Do not save the resulting credential-bearing
snapshot in the repository or an unprotected log.

Before declaring historical-version compatibility verified, run the standalone
suite on Ruby 2.4 and smoke-test the route in a compatible Rails 5.1 application.
Use the same process for any additional versions claimed as tested.

This record describes bounded test evidence, not a guarantee that arbitrary
application middleware, monkey patches, OS failures or resource exhaustion
cannot affect a diagnostic request.
