# Changelog

## 0.2.0

- Remove the Gemfile.lock inventory and all lockfile-reading code; retain only
  activated gems from Gem.loaded_specs.
- Omit non-allowlisted action_dispatch request-environment keys, including
  secret_key_base, legacy secret_token, key generators and cookie rotations.
  Also omit rack.session.options, which can contain signing secrets.
- Add ordered, signed `what` selection with nested JSON-object paths. Defaults
  exclude loaded_features, load_path, gems and environment; excluded collectors
  do not run. Secret omissions cannot be overridden by selectors.
- End displayed output with gc, yjit, runtime, application and request without
  moving GC/YJIT sampling later.
- Document explicit require in routes and Bundler's automatic-loading behavior.
- Add regression tests for selection, secret exclusions, non-interference and
  an optional local-only Bundler loading smoke test.

## 0.1.0

Initial implementation: standalone Rack endpoint, bounded request-body capture,
full request headers/environment, activated and locked gem inventories,
best-effort Rails/runtime/GC/YJIT/Linux collectors, defensive serialization,
and no automatic Rails integration or service connections.
