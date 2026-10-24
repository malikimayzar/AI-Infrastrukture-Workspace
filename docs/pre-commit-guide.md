# Pre-commit Hooks Guide

## Installation

Pre-commit hooks are already configured in `.pre-commit-config.yaml`. To install them:

```bash
# Install pre-commit framework (already done in venv)
pip install pre-commit

# Install the hooks
pre-commit install
```

## What Gets Checked

### Python Files
- **Black**: Code formatting (enforces consistent style)
- **Flake8**: Linting (syntax errors, unused imports, etc.)

### Go Files
- **golangci-lint**: Comprehensive Go linting (multiple linters combined)

### Shell Scripts
- **ShellCheck**: Shell script linting (common bugs, portability issues)

### Dockerfiles
- **Hadolint**: Dockerfile best practices

### YAML/JSON/TOML Files
- **Syntax validation**: Ensures files are well-formed

### Markdown Files
- **Markdownlint**: Consistent markdown formatting

### General
- **Trailing whitespace**: Removes trailing spaces
- **End-of-file-fixer**: Ensures files end with newline
- **Check for large files**: Prevents committing files > 1MB
- **Check merge conflicts**: Detects unresolved merge conflict markers

## Usage

### Automatic (Recommended)
Hooks run automatically when you run `git commit`. If a hook fails, the commit is blocked.

### Manual
Run hooks on all files manually:
```bash
pre-commit run --all-files
```

Run on specific files:
```bash
pre-commit run --files path/to/file.py
```

### Update Hooks
Update hooks to latest versions:
```bash
pre-commit autoupdate
```

### Skip Hooks (Not Recommended)
If you need to skip hooks (use sparingly):
```bash
git commit --no-verify -m "message"
```

## Troubleshooting

### Hook Fails
1. Fix the issues reported by the hook
2. Many hooks auto-fix (e.g., black, markdownlint)
3. Run `pre-commit run --all-files` to verify fixes

### Go Linter Not Found
Ensure golangci-lint is installed:
```bash
which golangci-lint
# If not found, install:
curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b ~/.local/bin v1.59.1
```

### Python Linter Not Found
Ensure black and flake8 are installed in venv:
```bash
pip install black flake8
```

## Customization

To disable specific hooks temporarily, comment them out in `.pre-commit-config.yaml`.

To add new hooks, follow the format in the config file. See [pre-commit.com](https://pre-commit.com/) for available hooks.
