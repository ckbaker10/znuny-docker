# znuny-base

Base image for Znuny, built on Debian 13 (Trixie) slim. Contains all system packages and Perl modules required to run Znuny, including modules that must be installed from CPAN because they are not packaged in Debian.

The main [Dockerfile](Dockerfile) uses this as its base (`FROM ghcr.io/ckbaker10/znuny-base:2.0`), so the lengthy apt install and compile steps only run when dependencies actually change — not on every Znuny version build.

| Tag | Debian | Notes |
|---|---|---|
| `2.0` | 13 (Trixie) | Crypto modules from apt, build tools removed after the CPAN step, no `DBD::ODBC` (dropped from Debian 13; only needed for MS-SQL) |
| `1.0` | 12 (Bookworm) | Previous base |

## Perl modules installed via cpanm

These are not packaged in Debian 13:

| Perl module | Reason |
|---|---|
| `Net::SAML2` | Needed for SAML authentication; pulls `XML::Sig`, `XML::Enc` and further SAML dependencies |
| `Jq` | Needed for generic interface condition checking |

`CryptX`, `Crypt::JWT`, `Crypt::OpenSSL::RSA` and `Crypt::OpenSSL::X509` come from the Debian 13 packages, which are recent enough (the Debian 12 based `1.0` image had to compile them).

The MariaDB 11.8 client in Debian 13 requires TLS by default; the base image sets `skip-ssl` for MariaDB clients because the bundled `mariadb` service has no TLS.

---

## Rebuilding and pushing

Only rebuild this image when you change `Dockerfile.base` (i.e. when Perl dependencies change) or to pick up Debian security updates. Bump the tag version (`2.0`, `2.1`, etc.) and update the `FROM` line in [Dockerfile](Dockerfile) to match.

Before pushing, run the end-to-end test (`tests/e2e/run.sh`); it builds this image locally and runs Znuny on top of it.

### Via GitHub Actions (preferred)

Push a `base-v<version>` tag; [build-base.yml](../.github/workflows/build-base.yml) builds `Dockerfile.base` and pushes `ghcr.io/<owner>/znuny-base:<version>` with the built-in `GITHUB_TOKEN`. The tag must match the `FROM` line in [Dockerfile](Dockerfile), and the base must be published before the Znuny version tag that uses it.

```bash
git tag base-v2.0
git push origin base-v2.0
```

If the package was first pushed by hand, the workflow can only write to it after granting this repository access: package settings → **Manage Actions access** → add the repository with the **Write** role.

### Manually

### 1. Create a GitHub personal access token

GitHub → **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)** → **Generate new token (classic)**

Required scope: `write:packages`

### 2. Log in to the GitHub Container Registry

```bash
echo "YOUR_GITHUB_TOKEN" | docker login ghcr.io -u ckbaker10 --password-stdin
```

### 3. Build the image

```bash
docker build \
  -f znuny/Dockerfile.base \
  -t ghcr.io/ckbaker10/znuny-base:2.0 \
  znuny/
```

### 4. Push the image

```bash
docker push ghcr.io/ckbaker10/znuny-base:2.0
```

### 5. Update the main Dockerfile

If you bumped the tag, update the `FROM` line in [Dockerfile](Dockerfile):

```dockerfile
FROM ghcr.io/ckbaker10/znuny-base:2.1
```

---

## Making the package public

By default ghcr.io packages are private. To allow the GitHub Actions worker to pull it without extra credentials:

GitHub → **Your profile** → **Packages** → select `znuny-base` → **Package settings** → **Change visibility** → **Public**
