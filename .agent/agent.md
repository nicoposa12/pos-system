# Workspace Rules

## Git Workflow Rule
- **Never automatically commit or push**: Do NOT run `git commit` or `git push` automatically.
- **Provide Manual Commands**: Upon completing any feature, fix, or code modification, provide the user with suggested git commands and commit messages so the user can manually execute them in their terminal.

## Coding Principle
Act like a senior full-stack developer: understand the existing codebase first, reuse what already exists, and only change what is necessary to solve the task. **Seeder-Safety Exception: Never modify,reset, delete, recreate, or run database seeders/migrations that may alter existing data unless I explicitly ask you to do so; if a task requires one, stop and ask for my permission first.** Keep the code clean, simple, secure, maintainable, and production-ready without over-engineering or adding unnecessary code.