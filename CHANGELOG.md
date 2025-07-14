# Changelog

All notable changes to this project will be documented in this file.

## [0.2.6]  - 2025-07-14

### Added

- Anthropic adapter (#14)

### Fixed

- correctly handle ecto default values on JSON schema (#15)

### Fixed
- Moved `required_fields` option to be an adapter specific config (gemini) (#12)

## [0.2.5]  - 2025-05-29

### Fixed
- Moved `required_fields` option to be an adapter specific config (gemini) (#12)

## [0.2.4]  - 2025-04-28

### Added
- Added `required_fields` option to `Mentor.Ecto.Schema` (#11)

## [0.2.3]  - 2025-04-16

### Added
- Added Google Gemini adapter for structured output support

## [0.2.2] - 2025-04-14

### Changes
- Minor bug fixes and improvements

## [0.2.1] - 2025-02-15

### Fixed
- Fixed minor bugs in OpenAI adapter
- Improved error handling

## [0.2.0] - 2025-01-28

### Added
- Added `configure_http_client/3` function to provide a more flexible way to configure HTTP clients
- Added type specifications for all public functions

### Changed
- **Breaking**: Removed `adapter_config` from `start_chat_with!/2` options. Configuration should now be done through `configure_adapter/2`
- Improved error handling for HTTP client validation
- Enhanced error handling for better insight into validation failures
- Restructured the codebase for better maintainability

### Fixed
- Fixed Dialyzer warnings across the codebase
- Fixed type specifications to be more accurate and complete

## [0.1.3] - 2025-01-22

### Added
- Added HTTP options configuration support for OpenAI adapter
- Added configurable timeouts for HTTP requests

### Changed
- Improved HTTP client configuration handling
- Enhanced documentation and examples

## [0.1.2] - 2025-01-22

### Added
- Added temperature configuration option for OpenAI adapter
- Added proper HTTP timeout configurations

### Fixed
- Fixed module loading issues with `Code.ensure_loaded?/1`
- Fixed custom type handling in JSON Schema generation

### Changed
- Improved error handling in custom type implementations
- Enhanced documentation for custom types

## [0.1.1] - 2025-01-21

### Added
- Added support for custom `llm_description/0` callback
- Added new parser implementation for better field documentation validation
- Added comprehensive documentation and examples
- Added evaluation modules for testing and demonstration

### Changed
- Simplified the parser implementation
- Improved documentation parsing and validation
- Enhanced error messages for missing field documentation

### Fixed
- Fixed documentation validation for nested fields
- Fixed schema field parsing

All these changes follow semantic versioning principles, where:
- 0.2.0 includes breaking changes to the API
- 0.1.1 through 0.1.3 add new features and fixes in a backward-compatible way

## [0.1.0] - 2025-01-20

### Added

- Initial release of Mentor.
  - Provides a high-level API to generate structured outputs based on various schemas, including raw maps, structs, and `Ecto` schemas.
  - Implements the `Mentor.LLM.Adapter` behaviour for integrating with different Large Language Models (LLMs).
  - Includes an adapter for OpenAI's language models.
  - Supports defining and validating data structures using the `Mentor.Schema` protocol.
  - Offers basic debugging capabilities.

> Note: This changelog follows the principles of [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
