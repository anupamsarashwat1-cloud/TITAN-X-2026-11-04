# Contributing to SMVDU TITAN-X

## Engineering Rules of Engagement
1. **Source Integrity**: Never modify historical reference repositories. All changes must occur on designated feature/remediation branches.
2. **Verification First**: Never mark a module verified merely because it compiles. All changes require reproducible simulation logs with zero unknown (`X`) states.
3. **No Placeholders**: Never introduce dummy counters or unconditional PASS assertions as substitutes for real hardware logic.
4. **Documentation**: Every module must have a corresponding, accurate `README.md` describing its declaration, parameters, ports, timing, and verified behavior.
5. **Git Workflow**: Commit messages must be structured (`feat:`, `fix:`, `docs:`, `chore:`) and explain the technical rationale.
