# Changelog

## 0.2.1

- Accept bare category and dotted-path names as inclusion rules; `-` still
  excludes. Explicit `+` remains accepted for compatibility. Plain `what` URLs
  no longer require percent-encoded plus signs.
- Add `-request.body` to the default selection. Default diagnostics do not call
  the body collector or read rack.input. Select request.body, request or all
  to restore bounded body capture; later exclusions still take precedence.
- Update examples, agent guidance and regression tests for the new defaults,
  unsigned selectors, legacy signed queries and cached-body omission.

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
