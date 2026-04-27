# Git Hooks Implementation Guide

## Overview

This project implements git hooks to enforce code quality, security, and consistency standards. Git hooks are scripts that run automatically at specific points in the git workflow.

## Scope of Git Hooks

### What Git Hooks Provide

1. **Code Quality Assurance**
   - YAML syntax validation
   - Helm chart linting and template validation
   - ArgoCD manifest validation

2. **Security**
   - Secret detection (passwords, API keys, tokens)
   - Hardcoded credential detection
   - Sensitive file pattern matching
   - Production secret placeholder detection

3. **Commit Message Standards**
   - Enforces Conventional Commits format
   - Validates commit message structure
   - Encourages clear, descriptive commit messages

4. **Pre-Push Validation**
   - Comprehensive validation before pushing to remote
   - Protected branch warnings
   - Production-specific checks

## Implemented Hooks

### 1. Pre-Commit Hook

**Triggers:** Before creating a commit

**Validations:**
- YAML syntax validation (using yamllint or Python)
- Secret detection (passwords, API keys, tokens, private keys)
- Hardcoded JWT secret detection
- Helm template validation (if Chart.yaml or values files changed)
- Dependency updates

**Security Benefits:**
- Prevents accidental commit of secrets
- Catches hardcoded credentials before they reach the repository
- Ensures YAML files are syntactically correct
- Validates Helm charts can be rendered successfully

### 2. Commit-Message Hook

**Triggers:** After commit message is written but before commit is created

**Validations:**
- Conventional Commits format compliance
- Commit message structure (type(scope): subject)
- Subject line length (≤50 characters recommended)
- Imperative mood enforcement
- Blank line between subject and body

**Allowed Types:**
- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation changes
- `style` - Code style changes
- `refactor` - Code refactoring
- `test` - Adding or updating tests
- `chore` - Maintenance tasks
- `ci` - CI/CD changes
- `perf` - Performance improvements
- `build` - Build system changes

**Examples:**
```
feat(user-service): add JWT authentication
fix(mongodb): resolve connection timeout issue
docs: update deployment guide
chore(secrets): rotate production secrets
```

**Security Benefits:**
- Enforces consistent commit history
- Makes code reviews more effective
- Enables automated changelog generation
- Improves traceability of changes

### 3. Pre-Push Hook

**Triggers:** Before pushing to remote repository

**Validations:**
- Comprehensive Helm linting (dev and prod environments)
- Helm template validation (dev and prod environments)
- ArgoCD manifest validation
- Sensitive file detection
- Production secret placeholder detection
- Protected branch warnings
- Test execution (if test script exists)

**Security Benefits:**
- Final validation before code leaves local environment
- Prevents pushing broken configurations
- Catches placeholder secrets in production
- Warns about pushes to protected branches
- Ensures all validations pass before remote push

## Setup Instructions

### Option 1: Using Setup Script (Recommended)

**For Linux/Mac:**
```bash
cd d:\CapsOnProject\ChapterOne-Helm\helm
bash scripts/setup-git-hooks.sh
```

**For Windows (PowerShell):**
```powershell
cd d:\CapsOnProject\ChapterOne-Helm\helm
.\scripts\setup-git-hooks.ps1
```

### Option 2: Manual Installation

```bash
# Navigate to repository root
cd d:\CapsOnProject\ChapterOne-Helm\helm

# Copy hooks to .git/hooks
cp .githooks/pre-commit .git/hooks/
cp .githooks/commit-msg .git/hooks/
cp .githooks/pre-push .git/hooks/

# Make hooks executable (Linux/Mac)
chmod +x .git/hooks/pre-commit
chmod +x .git/hooks/commit-msg
chmod +x .git/hooks/pre-push
```

### Option 3: Git Configuration (Team-Wide)

To automatically use hooks from `.githooks` directory for all contributors:

```bash
git config core.hooksPath .githooks
```

This tells git to look for hooks in the `.githooks` directory instead of `.git/hooks`, making it easier to share hooks across the team.

## Bypassing Hooks

**Temporary bypass (use with caution):**
```bash
# Bypass pre-commit hook
git commit --no-verify -m "message"

# Bypass pre-push hook
git push --no-verify
```

**Warning:** Bypassing hooks should only be done in exceptional cases and with full understanding of the risks.

## Security Justification

### 1. Secret Leak Prevention
- **Problem:** Developers accidentally commit secrets (API keys, passwords, tokens)
- **Solution:** Pre-commit hook scans for secret patterns before commit
- **Impact:** Prevents secrets from entering git history, which is critical as git history is difficult to clean

### 2. Configuration Validation
- **Problem:** Invalid YAML or Helm templates can cause deployment failures
- **Solution:** Hooks validate syntax and render templates before commit/push
- **Impact:** Catches configuration errors early, preventing deployment failures

### 3. Production Safety
- **Problem:** Placeholder secrets in production configurations
- **Solution:** Pre-push hook checks for placeholder values in production branches
- **Impact:** Prevents deployment with default/placeholder credentials

### 4. Code Quality Standards
- **Problem:** Inconsistent commit messages make code review and debugging difficult
- **Solution:** Commit-msg hook enforces Conventional Commits format
- **Impact:** Improves code review efficiency, enables automated changelog generation

### 5. Protected Branch Protection
- **Problem:** Accidental pushes to main/production branches
- **Solution:** Pre-push hook warns and requires confirmation for protected branches
- **Impact:** Reduces risk of accidental production deployments

## Dependencies

### Required Tools
- **git** - Version control system
- **python3** - For YAML validation (fallback if yamllint not available)
- **helm** - For Helm chart validation

### Optional Tools
- **yamllint** - Enhanced YAML linting
  ```bash
  # Install on Linux/Mac
  pip install yamllint
  
  # Install on Windows
  pip install yamllint
  ```

## Troubleshooting

### Hook Not Executing
**Problem:** Hook script not running
**Solution:**
- Ensure hooks are executable: `chmod +x .git/hooks/*`
- Check git configuration: `git config core.hooksPath`
- Verify hook file permissions

### YAML Validation Fails
**Problem:** YAML syntax errors
**Solution:**
- Run `yamllint <file>` to see specific errors
- Check indentation (should be 2 spaces)
- Verify no trailing spaces

### Helm Validation Fails
**Problem:** Helm template errors
**Solution:**
- Run `helm lint . -f values-dev.yaml` to see specific errors
- Check Chart.yaml syntax
- Verify all required values are defined

### Secret Detection False Positives
**Problem:** Legitimate strings flagged as secrets
**Solution:**
- Review the secret patterns in the hook
- Add exceptions if needed (update the hook script)
- Use environment variables instead of hardcoding

## Best Practices

1. **Never bypass hooks** unless absolutely necessary
2. **Review hook failures** carefully before bypassing
3. **Keep hooks updated** as project evolves
4. **Test hooks locally** before pushing
5. **Use CI/CD validation** as a safety net (GitHub Actions already validate)
6. **Educate team members** about hook purpose and usage
7. **Review hook logs** to understand validation failures

## Integration with CI/CD

Git hooks provide local validation, while CI/CD (GitHub Actions) provides remote validation:

- **Git Hooks:** Fast feedback, prevents bad commits locally
- **CI/CD:** Safety net, validates in clean environment, enforces standards for PRs

Both work together to ensure code quality and security.

## Maintenance

To update hooks:
1. Edit files in `.githooks/` directory
2. Re-run setup script or copy to `.git/hooks/`
3. Test changes locally
4. Commit updated hooks to repository

## Related Documentation

- [DEPLOYMENT.md](./DEPLOYMENT.md) - Deployment guide
- [NETWORK_POLICY_GUIDE.md](./NETWORK_POLICY_GUIDE.md) - Network policies
- [NAMESPACE_STRATEGY.md](./NAMESPACE_STRATEGY.md) - Namespace strategy
