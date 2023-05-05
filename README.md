# Trilogy Adapter

Active Record database adapter for [Trilogy](https://github.com/github/trilogy)

This gem offers Trilogy support for versions of ActiveRecord prior to 7.1. Currently supports:

- Rails v7.0.x

## Requirements

- [Ruby](https://www.ruby-lang.org) 2.7 or higher
- [Active Record](https://github.com/rails/rails) 7.0.x
- [Trilogy](https://github.com/github/trilogy) 2.4.0 or higher

## Setup

* Add the following to your Gemfile:

  ```rb
  gem "activerecord-trilogy-adapter"
  ```

* Update your database configuration (e.g. `config/database.yml`) to use
  `trilogy` as the adapter.

## Versioning

Read [Semantic Versioning](https://semver.org) for details. Briefly, it means:

- Major (X.y.z) - Incremented for any backwards incompatible public API changes.
- Minor (x.Y.z) - Incremented for new, backwards compatible, public API enhancements/fixes.
- Patch (x.y.Z) - Incremented for small, backwards compatible, bug fixes.

## Code of Conduct

Please note that this project is released with a [CODE OF CONDUCT](CODE_OF_CONDUCT.md). By
participating in this project you agree to abide by its terms.

## Contributions

Read [CONTRIBUTING](CONTRIBUTING.md) for details.

## License

Released under the [MIT License](LICENSE.md).
