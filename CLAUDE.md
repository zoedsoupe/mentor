# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mentor is an Elixir library that provides a high-level API for generating structured output from Large Language Models (LLMs). It acts as a bridge between traditional software and AI models, allowing developers to generate JSON output that conforms to predefined schemas with automatic validation and retry logic.

## Development Commands

```bash
# Install dependencies
mix deps.get
mix deps.compile

# Run tests
mix test
mix test test/path/to/specific_test.exs  # Run specific test file

# Code quality checks
mix credo              # Static code analysis
mix dialyzer           # Type checking (first run: mix dialyzer --plt)

# Generate documentation
mix docs

# Interactive development
iex -S mix             # Start interactive shell with project loaded

# Compile
mix compile
```

## Architecture Overview

### Core Components

1. **Mentor Module** (`lib/mentor.ex`)
   - Main entry point and API
   - Implements fluent/builder pattern for configuration
   - Manages the chat lifecycle: `start_chat_with!` → `configure_adapter` → `append_message` → `complete`

2. **Adapter Pattern**
   - `Mentor.LLM.Adapter` behaviour - defines interface for LLM providers
   - `Mentor.HTTPClient.Adapter` behaviour - defines interface for HTTP clients
   - Implementations in `lib/mentor/llm/adapters/` (OpenAI, Gemini)

3. **Schema System**
   - `Mentor.Schema` behaviour - defines interface for schemas
   - `Mentor.Ecto.Schema` - Ecto schema integration
   - Automatic JSON schema generation from Ecto schemas
   - Schema documentation is automatically included in prompts

4. **Validation & Retry Logic**
   - Automatic validation of LLM responses against schemas
   - Exponential backoff retry mechanism (default 3 retries)
   - Formula: `min(max_backoff, (base_backoff * 2) ^ retry_count)`

### Key Design Decisions

1. **Extensibility**: New LLM providers can be added by implementing the `Mentor.LLM.Adapter` behaviour
2. **Optional Dependencies**: Ecto and Peri are optional - only Ecto schemas currently supported
3. **Composable API**: All configuration methods return the updated struct for chaining
4. **Error Handling**: Uses custom exceptions (`Mentor.ConfigurationError`, `Mentor.ResponseValidationError`)

### Testing Strategy

- Uses Mox for mocking HTTP clients
- Test files mirror the source structure in `test/`
- Mock modules defined in `test/support/mocks.ex`

### Adding New Features

When adding new LLM adapters:
1. Implement the `Mentor.LLM.Adapter` behaviour
2. Add adapter module to `lib/mentor/llm/adapters/`
3. Update configuration validation in `Mentor.configure_adapter/2`
4. Add corresponding tests using mocked HTTP responses

When modifying schema handling:
1. Check `Mentor.Ecto.Schema` for Ecto-specific logic
2. Ensure compatibility with JSON schema generation
3. Update validation logic if needed