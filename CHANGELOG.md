# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/).

## [Unreleased]

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
