# Trilogy Adapter

Ruby on Rails Active Record database adapter for [Trilogy](https://github.com/trilogy-libraries/trilogy), a client library for MySQL-compatible database servers, designed for performance, flexibility, and ease of embedding.

This gem offers Trilogy support for versions of Active Record prior to v7.1. Currently supports:

- ⚠️ Rails v7.1+ includes Trilogy support by default making this gem unnecessary
- ✅ Rails v7.0.x
- ✅ Rails v6.1.x
- ✅ Rails v6.0.x

## Requirements

- [Ruby](https://www.ruby-lang.org) v2.7 or higher
- [Active Record](https://github.com/rails/rails) v6.0.x or higher
- [Trilogy](https://github.com/trilogy-libraries/trilogy) v2.4.0 or higher, which is included as a dependency of this gem.

## Setup

1. Add the following to your `Gemfile` and run `bundle install`:

    ```rb
    # Gemfile
    gem "activerecord-trilogy-adapter"
    ```
2. Update your application's database configuration to use `trilogy` as the adapter:

   ```yaml
   # config/database.yml
   adapter: trilogy
   ```

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
