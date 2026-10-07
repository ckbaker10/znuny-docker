# Release migration acceptance: 2026-10-07

Target: locally built Znuny **7.3.7**, Debian 13, base **2.0**. All three
acceptance cases passed. No images were published by this test.

| Case | Storage | Result |
|---|---|---|
| 7.1.3 fullbackup → fresh 7.2.3 → 7.3.7 | ArticleStorageFS | PASS |
| 7.2.3 fullbackup → fresh 7.3.7 | ArticleStorageDB | PASS |
| 7.3.1 fresh install → in-place 7.3.7 patch update | Standard database storage | PASS |

Both backup cases retained ticket ID 2, article ID 2, the article body, storage
backend and exact binary attachment bytes. Attachment SHA-256:
`a62b6a01779d77da64c5f3ffcee7ce2ad09dbf5ed03ac103eb88d9d2626005a7`.
Admin login, database connectivity, daemon, RELEASE and version marker passed.
Patch E2E additionally checked required Perl modules, rejection of a wrong
password, customer interface, ticket preservation and absence of errors after
startup. Only synthetic data was used. All test containers/networks were removed.

## Reproduction and evidence

From the repository root:

```bash
python3 /home/developer/.codex/skills/analysis-evidence/scripts/evidence.py \
  --output work/release-acceptance-repeat \
  --tool-version 'podman 4.9.3; podman-compose 1.0.6; Python 3.12.3' \
  --input README.md --input tests/migration/run.py \
  --input tests/migration/fixture.pl --input tests/migration/release.sh \
  --input tests/e2e/run.sh -- bash tests/migration/release.sh 7.3.7
```

Without the host evidence helper, run `bash tests/migration/release.sh 7.3.7`.
The successful recorded invocation used output directory
`work/release-acceptance-r4/`: metadata, exact argv, stdout and stderr remain
ignored. Exit status **0**; host epochs **1791361655.7220914–1791361971.212374**,
315.49 seconds including builds. The wrapper measured the acceptance phase with
`date +%s`: **251 seconds**.

The tested README input hash was
`4106ad415dbc8637533369d9fb90ad48fdaaed6900d7b27fbc21e489de5449b9`;
its result-description paragraph was updated after the test. Executed migration
commands are unchanged. Other recorded input hashes:

| Input | SHA-256 |
|---|---|
| tests/migration/run.py | `abd78081a405a24b0ac07b9e85c72a24c657cc4f576a2ce7a94ceabfdd342dfc` |
| tests/migration/fixture.pl | `955888ee4deb8b001682262df9edce9f1af8303a3c15e2b291a6c2d84804f613` |
| tests/migration/release.sh | `f772b643318318efe1313ac64c1d5bdec656ad3bd770970c1a3561dba604e1d2` |
| tests/e2e/run.sh | `2e990dc14959a1117165cd5d0deb5af2d1e2664081a058983ae67e400e65ae0d` |

Container image IDs from `podman image inspect --format '{{.Id}}' IMAGE`:

| Image | ID |
|---|---|
| ghcr.io/ckbaker10/znuny-base:2.0 | `2b209edf5ce618fc2fdeaec802e93bfb97fbd2013faac8cee77f1ffe68b4d909` |
| localhost/znuny-migration-test:7.1.3 | `64ff5dc9cf1d6128837e02b429e7779dca8783250016aedb01e3f77099e6658c` |
| localhost/znuny-migration-test:7.2.3 | `720d9f452d127d0e7981ea481d085e7c20220a4fcac0f17f85185745a43a449e` |
| localhost/znuny-migration-test:7.3.7 | `b4342b4efd8dc47a365c7141058994661daa5c7631ccb3f772311dea812baf1f` |

The retained synthetic backups and result summaries are under
`work/migration-7.1.3-ArticleStorageFS-1791361720/` and
`work/migration-7.2.3-ArticleStorageDB-1791361720/`. The backups in each
`target/volumes/backups/source/` directory have these SHA-256 hashes, recorded
using `podman unshare sha256sum FILE`:

| Source | File | SHA-256 |
|---|---|---|
| 7.1.3 | Config.tar.gz | `cdb6fb326baf88b23778ebe726e5702dfdb4f19dbda94b3fab021600b6ee4be0` |
| 7.1.3 | Application.tar.gz | `9995c92a18c44748e916b66ffca0ce006e48098e536b5319884b95020e16dcb1` |
| 7.1.3 | DatabaseBackup.sql.gz | `a72a2d2799dda5d265aa93e4537acd50643ed2582b05927834e9dd5a0c188b19` |
| 7.2.3 | Config.tar.gz | `a3da887124e729914f968ed7cb59843b843065c3a7b0e3cbf8ea1cbb69337a11` |
| 7.2.3 | Application.tar.gz | `b9e72aa47f4046f371974bc3a94ac0734d0244ccd810e6c5c33cea21598cf39a` |
| 7.2.3 | DatabaseBackup.sql.gz | `c8848a2bdd2251d980261ece870fdda60bcf761ab2dfa924302477cf993088e0` |

## Corrections established by the test

- One-off Compose containers need `--non-interactive` on every migration run
  after the verified backup; otherwise the migration can wait for confirmation.
- Restore generated source settings (`Kernel/Config/Files/ZZZAAuto.pm`) along
  with Config.pm. Keep the target XML definitions/application code. The 7.2
  migration needs these settings before it creates the new communication channel.
- Let the migration rebuild configuration in its own sequence. Rebuilding 7.2
  defaults against an unmigrated 7.1 database can create duplicate settings.

ShellCheck 0.9.0, actionlint, Python syntax and local documentation links passed.
Publishing is gated by the reusable CI acceptance workflow; the GitHub jobs
themselves were not triggered by this local run.

Coverage: source fixtures were created with this project's Debian 13 images,
standard MySQL/MariaDB and standard article paths. No custom add-ons, custom
Kernel/skins, external article paths, PostgreSQL or complete IdP authentication
were tested. See [suite instructions](README.md) for the mandatory release gate.
