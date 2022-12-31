# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added

- Support Rails 6.1 and 7.0

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
