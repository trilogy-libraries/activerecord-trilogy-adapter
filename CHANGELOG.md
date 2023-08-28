# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## 3.1.2

### Fixed

- Correct reference to materialize_transactions in with_trilogy_connection #61

## 3.1.1

### Changed

- Remove translation of exception on reconnect. #49
- Backport Rails 7.1a refactors and tweaks. #50, #51, #57, #58, #59

### Fixed

- Fix #53 - Implement dbconsole support. #55
- Fix #54 - Apply connection configuration. #56

## 3.1.0

### Changed

- Added support for Rails 6.0 and 6.1. #42
- Backport Rails 7.1a refactors and tweaks. #44, #45, #46, #47, #48

### Fixed

- Remove translation of exception on reconnect to fix Rails test parallel tests. #49

## 3.0.0

### Changed

- Added support for Rails 7.0 and removed support for prerelease Rails 7.1 because this adapter was merged into Rails. #26

## 2.2.0

### Changed

- Bump minimum Trilogy version to 2.3.0. #32
- Start using the new Trilogy 2.3.0 error classes. #24
- Rely on the upstream `execute` method (which includes an `allow_retry` option). #12
- Rely on the upstream `raw_execute` method (which includes a new warning feature). #29
- Replace custom dbconsole patch with `TrilogyAdapter::Connection#trilogy_adapter_class`. #8

### Fixed

- Don't retain the old connection if reconnect fails. #13
- Call `super` in `TrilogyAdapter#disconnect!` to ensure we properly reset state. #11

## 2.1.0

### Added

- Support string ssl modes.

### Fixed

- Correct version constraint for activerecord.
- Require a valid connection when quoting a string.
- Treat IOError as a connectivity-related error.
- Disable prepared statements, since Trilogy doesn't yet support them.

## 2.0.0

### Added

- Initial release of the adapter.
